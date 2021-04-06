=head1 LICENSE
 
See the NOTICE file distributed with this work for additional information
regarding copyright ownership.
 
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
 
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 
=cut
package Gene2phenotype::Model::GenomicFeatureDiseasePanel; 
use Mojo::Base 'MojoX::Model';

sub add {
  my $self = shift;
  my $gfd_id = shift;
  my $panel = shift;
  my $confidence_value = shift;
  my $email = shift;

  my $registry = $self->app->defaults('registry');
  my $GFD_panel_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDiseasePanel');
  my $user_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'user');

  my $gfd_panel =  Bio::EnsEMBL::G2P::GenomicFeatureDiseasePanel->new(
    -genomic_feature_disease_id => $gfd_id,
    -panel => $panel,
    -confidence_value => $confidence_value,
    -adaptor => $GFD_panel_adaptor,
  );
  my $user = $user_adaptor->fetch_by_email($email);
  $gfd_panel = $GFD_panel_adaptor->store($gfd_panel, $user);
  return $gfd_panel;
}

1;
