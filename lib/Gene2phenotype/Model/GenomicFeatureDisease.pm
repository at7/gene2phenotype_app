package Gene2phenotype::Model::GenomicFeatureDisease; 
use Mojo::Base 'MojoX::Model';

sub fetch_by_dbID {
  my $self = shift;
  my $dbID = shift;
  my $logged_in = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $GFD = $GFD_adaptor->fetch_by_dbID($dbID);

  my $GFDL_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturediseaselog');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my @logs = ();
  if ($logged_in) {
    my $GFD_logs = $GFDL_adaptor->fetch_all_by_GenomicFeatureDisease($GFD);  
    foreach my $log (@$GFD_logs) {
      my $created = $log->created;
      my $action = $log->action;
      my $user_id = $log->user_id;  
      my $user = $user_adaptor->fetch_by_dbID($user_id);
      my $user_name = $user->username;
      my $disease_confidence = $log->disease_confidence;
      push @logs, {created => $created, user => $user_name, disease_confidence => $disease_confidence, action => $action};
    }
  }

  my $panel = $GFD->panel;
  my $authorised = $GFD->is_visible;
  my $gene_symbol = $GFD->get_GenomicFeature->gene_symbol;
  my $gene_id = $GFD->get_GenomicFeature->dbID;

  my $disease_name = $GFD->get_Disease->name; 
  my $disease_id = $GFD->get_Disease->dbID;

  my $GFD_category = $self->_get_GFD_category($GFD);
  my $GFD_category_list = $self->_get_GFD_category_list($GFD);
  my $attributes = $self->_get_GFD_action_attributes($GFD, $logged_in);
  my $publications = $self->_get_publications($GFD);
  my $phenotypes = $self->_get_phenotypes($GFD);
  my $phenotype_ids_list = $self->get_phenotype_ids_list($GFD);
  my $organs = $self->_get_organs($GFD); 
  my $edit_organs = $self->_get_edit_organs($GFD, $organs); 

  my $add_GFD_action = $self->_get_GFD_action_attributes_list('add');
  my $add_AR_loop = $add_GFD_action->{AR};
  my $add_MC_loop = $add_GFD_action->{MC};

  return {
    panel => $panel,
    gene_symbol => $gene_symbol,
    gene_id => $gene_id,
    disease_name => $disease_name,
    disease_id => $disease_id,
    authorised => $authorised,
    GFD_id => $dbID,
    GFD_category => $GFD_category,
    GFD_category_list => $GFD_category_list,
    GFD_actions => $attributes,
    publications => $publications,
    phenotypes => $phenotypes,
    phenotype_ids_list => $phenotype_ids_list,
    organs => $organs,
    edit_organs => $edit_organs,
    add_AR_loop => $add_AR_loop,
    add_MC_loop => $add_MC_loop,
    logs => \@logs,
  };

}

sub duplicate {
  my $self = shift;
  my $GFD_id = shift;
  my $panel = shift;
  my $data = shift;
  my $email = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my $user = $user_adaptor->fetch_by_email($email);

  my $from_gfd = $GFD_adaptor->fetch_by_dbID($GFD_id);
 
  my $gf = $from_gfd->get_GenomicFeature;
  my $disease = $from_gfd->get_Disease;

  my $already_in_to_panel = $GFD_adaptor->fetch_by_GenomicFeature_Disease_panel($gf, $disease, $panel);
 
  if ($already_in_to_panel) {
    return [$already_in_to_panel, 'ENTRY_HAS_NOT_BEEN_DUPLICATED'];
  }
  
  # create new entry
  my $gfd_to_panel =  Bio::EnsEMBL::G2P::GenomicFeatureDisease->new(
    -panel => $panel,
    -disease_id => $disease->dbID,
    -genomic_feature_id => $gf->dbID,
    -DDD_category => $from_gfd->DDD_category,
    -adaptor => $GFD_adaptor,
  );
  $gfd_to_panel = $GFD_adaptor->store($gfd_to_panel, $user);
  
  foreach my $data_type (@$data) {
    if ($data_type eq 'gene_disease_attribs') {
      my $gfdaa = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseAction');

      # get all gene_disease_attribs 
      my $from_gfd_actions = $from_gfd->get_all_GenomicFeatureDiseaseActions;

      foreach my $from_gfd_action (@$from_gfd_actions) {
        my $new_GFD_action = Bio::EnsEMBL::G2P::GenomicFeatureDiseaseAction->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -allelic_requirement_attrib => $from_gfd_action->allelic_requirement_attrib,
          -mutation_consequence_attrib => $from_gfd_action->mutation_consequence_attrib,
          -user_id => undef,
        );
        $new_GFD_action = $gfdaa->store($new_GFD_action, $user);
      }
    } elsif ($data_type eq 'publications') {
      my $gfd_publication_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseasePublication');
      my $from_gfd_publications = $from_gfd->get_all_GFDPublications;
      foreach my $from_gfd_publication (@$from_gfd_publications) {
        my $new_GFDPublication = Bio::EnsEMBL::G2P::GenomicFeatureDiseasePublication->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -publication_id => $from_gfd_publication->get_Publication->dbID,
          -adaptor => $gfd_publication_adaptor,
        );
        $gfd_publication_adaptor->store($new_GFDPublication);
      }
    } elsif ($data_type eq 'phenotypes') {
      my $gfd_phenotype_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseasePhenotype');
      my $from_gfd_phenotypes = $from_gfd->get_all_GFDPhenotypes;
      foreach my $from_gfd_phenotype (@$from_gfd_phenotypes ) {
        my $new_GFDPhenotype = Bio::EnsEMBL::G2P::GenomicFeatureDiseasePhenotype->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -phenotype_id => $from_gfd_phenotype->get_Phenotype->dbID,
          -adaptor => $gfd_phenotype_adaptor,
        );
        $gfd_phenotype_adaptor->store($new_GFDPhenotype);
      }
    } elsif ($data_type eq 'organ_specificity') {
      my $gfd_organ_adaptor =  $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseOrgan');
      my $from_gfd_organs = $from_gfd->get_all_GFDOrgans;
      foreach my $from_gfd_organ (@$from_gfd_organs) {
       my $new_GFDOrgan = Bio::EnsEMBL::G2P::GenomicFeatureDiseaseOrgan->new(
          -genomic_feature_disease_id => $gfd_to_panel->dbID,
          -organ_id => $from_gfd_organ->get_Organ->dbID,
          -adaptor => $gfd_organ_adaptor,
        );
        $gfd_organ_adaptor->store($new_GFDOrgan);
      }
    } else {
      
    }
  } 

  return [$gfd_to_panel, 'DUPLICATED_ENTRY_SUC']; 
}

sub fetch_all_by_panel_restricted {
  my $self = shift;
  my $panel = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $gfds = $GFD_adaptor->fetch_all_by_panel_restricted($panel);
  my @results = ();
  foreach my $gfd (@$gfds) {
    push @results, {
      gene_symbol => $gfd->get_GenomicFeature->gene_symbol,
      disease_name => $gfd->get_Disease->name,
      GFD_id => $gfd->dbID,
    }; 
  }
  return \@results;
}

sub fetch_all_by_panel_without_publication {
  my $self = shift;
  my $panel = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $gfds = $GFD_adaptor->fetch_all_by_panel_without_publications($panel);
  my @results = ();
  foreach my $gfd (@$gfds) {
    push @results, {
      gene_symbol => $gfd->get_GenomicFeature->gene_symbol,
      disease_name => $gfd->get_Disease->name,
      GFD_id => $gfd->dbID,
    }; 
  }
  return \@results;
}

sub fetch_by_panel_GenomicFeature_Disease {
  my $self = shift;
  my $panel = shift;
  my $gf = shift;
  my $disease = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel); 
  my $gfd = $GFD_adaptor->fetch_by_GenomicFeature_Disease_panel_id($gf, $disease, $panel_id);
  return $gfd;
}

sub add {
  my $self = shift;
  my $panel = shift;
  my $gf = shift;
  my $disease = shift;
  my $category_attrib_id = shift;
  my $email = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel); 

  my $gfd =  Bio::EnsEMBL::G2P::GenomicFeatureDisease->new(
    -panel_attrib => $panel_id,
    -disease_id => $disease->dbID,
    -genomic_feature_id => $gf->dbID,
    -DDD_category_attrib => $category_attrib_id,
    -adaptor => $GFD_adaptor,
  );
  my $user = $user_adaptor->fetch_by_email($email);
  $gfd = $GFD_adaptor->store($gfd, $user);
  return $gfd;
}

sub delete {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicfeaturedisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);
  my $GFD = $GFD_adaptor->fetch_by_dbID($GFD_id); 
  $GFD_adaptor->delete($GFD, $user);
}

sub get_default_GFD_category_list {
  my $self = shift;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('DDD_Category');
  my @list = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    push @list, [$value => $id];
  }
  return \@list;
}

sub _get_GFD_category_list {
  my $self = shift;
  my $GFD = shift;
  my $GFD_category = $GFD->DDD_category;
  my $GFD_id = $GFD->dbID;
  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('DDD_Category');
  my @list = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    my $is_selected =  ($value eq $GFD_category) ? 'selected' : '';
    if ($is_selected) {
      push @list, [$value => $id, selected => $is_selected];
    } else {
      push @list, [$value => $id];
    }
  }
  return \@list;
}

sub _get_GFD_category {
  my $self = shift;
  my $GFD = shift;
  my $category = $GFD->DDD_category || 'Not assigned';
  return $category;
}

sub _get_GFD_action_attributes_list {
  my $self = shift;
  my $type = shift;
  my $GFD_action = shift;

  my @ARs = ();
  my $mutation_consequence = '';
  if ($type eq 'edit') {
    @ARs = split(',', $GFD_action->allelic_requirement);
    $mutation_consequence = $GFD_action->mutation_consequence;
  }

  my $registry = $self->app->defaults('registry');
  my $attribute_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'attribute');
  my $attribs = $attribute_adaptor->get_attribs_by_type_value('allelic_requirement');
  my @AR_tmpl = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    if ($type eq 'edit') {
      my $checked = (grep $_ eq $value, @ARs) ? 'checked' : '';
      push @AR_tmpl, {
        AR_attrib_id => $id,
        AR_attrib_value => $value,
        checked => $checked,
      };
    } else {
      push @AR_tmpl, {
        AR_attrib_id => $id,
        AR_attrib_value => $value,
      };
    }
  }

  $attribs = $attribute_adaptor->get_attribs_by_type_value('mutation_consequence');
  my @MC_tmpl = ();
  foreach my $value (sort keys %$attribs) {
    my $id = $attribs->{$value};
    if ($type eq 'edit') {
      my $selected = ($value eq $mutation_consequence) ? 'selected' : undef;
      if ($selected) {
        push @MC_tmpl, [$value => $id, selected => $selected];
      } else {
        push @MC_tmpl, [$value => $id];
      }
    } else {
      push @MC_tmpl, [ $value => $id ];
    }
  }
  return {AR => \@AR_tmpl, MC => \@MC_tmpl};
}

sub _get_GFD_action_attributes {
  my $self = shift;
  my $GFD = shift;
  my $logged_in = shift;
  my $registry = $self->app->defaults('registry');
  my $GFDAL_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'genomicFeatureDiseaseActionLog');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');


  my $GFD_actions = $GFD->get_all_GenomicFeatureDiseaseActions();
  my @actions = ();
  foreach my $gfda (@$GFD_actions) {
    my @logs = ();
    if ($logged_in) {
      my $gfda_logs = $GFDAL_adaptor->fetch_all_by_GenomicFeatureDiseaseAction($gfda);
      foreach my $log (@$gfda_logs) {
        my $created = $log->created;
        my $user_id = $log->user_id;
        my $user = $user_adaptor->fetch_by_dbID($user_id);
        my $user_name = $user->username;
        my $action = $log->action;
        my $allelic_requirement = $log->allelic_requirement || 'Not assigned';
        my $mutation_consequence = $log->mutation_consequence || 'Not assigned';
        push @logs, {created => $created, user => $user_name, ar => $allelic_requirement, mc => $mutation_consequence, action => $action};
      }
    }
    my $allelic_requirement = $gfda->allelic_requirement || 'Not assigned';
    my $mutation_consequence_summary = $gfda->mutation_consequence || 'Not assigned';
    my $edit_GFD_action = $self->_get_GFD_action_attributes_list('edit', $gfda);
    push @actions, {
      allelic_requirement => $allelic_requirement,
      mutation_consequence_summary => $mutation_consequence_summary,
      AR_loop => $edit_GFD_action->{AR},
      MC_loop => $edit_GFD_action->{MC},
      GFD_action_id => $gfda->dbID,
      logs => \@logs,
    };
  }

  return \@actions;
}

sub _get_publications {
  my $self = shift;
  my $GFD = shift;
  my @publications = ();

  my $GFD_publications = $GFD->get_all_GFDPublications;
  foreach my $GFD_publication (sort {$a->get_Publication->title cmp $b->get_Publication->title} @$GFD_publications) {
    my $publication = $GFD_publication->get_Publication;
    my $comments = $GFD_publication->get_all_GFDPublicationComments;
    my @comments_tmpl = ();
    foreach my $comment (@$comments) {
      push @comments_tmpl, {
        user => $comment->get_User()->username,
        date => $comment->created,
        comment_text => $comment->comment_text,
        GFD_publication_comment_id => $comment->dbID,
        GFD_id => $GFD->dbID,
      };
    }
    my $pmid = $publication->pmid;
    my $title = $publication->title;
    my $source = $publication->source;

    $title ||= 'PMID:' . $pmid;
    $title .= " ($source)" if ($source);

    push @publications, {
      comments => \@comments_tmpl,
      title => $title,
      pmid => $pmid,
      GFD_publication_id => $GFD_publication->dbID,
      GFD_id => $GFD->dbID,
    };
  }
  return \@publications;
}

sub _get_phenotypes {
  my $self = shift;
  my $GFD = shift;

  my @phenotypes = ();
  my $GFD_phenotypes = $GFD->get_all_GFDPhenotypes;
  foreach my $GFD_phenotype ( sort { $a->get_Phenotype()->name() cmp $b->get_Phenotype()->name() } @$GFD_phenotypes) {
    my $phenotype = $GFD_phenotype->get_Phenotype;
    my $stable_id = $phenotype->stable_id;
    my $name = $phenotype->name;
    my $comments = $GFD_phenotype->get_all_GFDPhenotypeComments;
    my @comments_tmpl = ();
    foreach my $comment (@$comments) {
      push @comments_tmpl, {
        user => $comment->get_User()->username,
        date => $comment->created,
        comment_text => $comment->comment_text,
        GFD_phenotype_comment_id => $comment->dbID,
        GFD_id => $GFD->dbID,
      };
    }

    push @phenotypes, {
      comments => \@comments_tmpl,
      stable_id => $stable_id,
      name => $name,
      GFD_phenotype_id => $GFD_phenotype->dbID,
    };
  }
  my @sorted_phenotypes = sort {$a->{name} cmp $b->{name}} @phenotypes;
  return \@phenotypes;
}

sub _get_organs {
  my $self = shift;
  my $GFD = shift;
  my @organ_list = ();
  my $organs = $GFD->get_all_GFDOrgans;
  foreach my $organ (@$organs) {
    my $name = $organ->get_Organ()->name;
    push @organ_list, $name;
  }
  return \@organ_list;
}

sub _get_edit_organs {
  my $self = shift;
  my $GFD = shift;  
  my $organ_list = shift;
 
  my $registry = $self->app->defaults('registry');
  my $organ_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'Organ');

  my %all_organs = map {$_->name => $_->dbID} @{$organ_adaptor->fetch_all};
  my @organs = (); 
  foreach my $value (sort keys %all_organs) {
    my $id = $all_organs{$value};
    my $checked = (grep $_ eq $value, @$organ_list) ? 'checked' : '';
    push @organs, {
      organ_id => $id,
      organ_name => $value,
      checked => $checked,
    };
  }
  return \@organs;
}

sub get_phenotype_ids_list {
  my $self = shift;
  my $GFD = shift;
  my @phenotype_ids = ();
  my $GFDPhenotypes = $GFD->get_all_GFDPhenotypes;
  foreach my $GFDPhenotype (@$GFDPhenotypes) {
    push @phenotype_ids, $GFDPhenotype->get_Phenotype->dbID;
  }
  return join(',', @phenotype_ids);
}

sub update_GFD_category {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;
  my $category_attrib_id = shift;
  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);
  my $GFD = $GFD_adaptor->fetch_by_dbID($GFD_id);
  $GFD->DDD_category_attrib($category_attrib_id);
  $GFD_adaptor->update($GFD, $user); 
}

sub update_organ_list {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;
  my $organ_id_list = shift;

  my $registry = $self->app->defaults('registry');
  my $GFDOrgan_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseaseOrgan');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);

  $GFDOrgan_adaptor->delete_all_by_GFD_id($GFD_id);
  foreach my $organ_id (split(',', $organ_id_list)) {
    my $GFDOrgan =  Bio::EnsEMBL::G2P::GenomicFeatureDiseaseOrgan->new(
      -organ_id => $organ_id,
      -genomic_feature_disease_id => $GFD_id,
      -adaptor => $GFDOrgan_adaptor, 
    );
    $GFDOrgan_adaptor->store($GFDOrgan);
  }  
}

sub update_visibility {
  my $self = shift;
  my $email = shift;
  my $GFD_id = shift;
  my $visibility = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDisease');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');
  my $user = $user_adaptor->fetch_by_email($email);

  my $is_visible = $visibility eq 'authorised' ? 1 : 0;
  my $GFD = $GFD_adaptor->fetch_by_dbID($GFD_id);
  $GFD->is_visible($is_visible);
  $GFD_adaptor->update($GFD, $user); 
}

1;
