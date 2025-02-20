#!/usr/bin/env perl

use Carp;
use strict;
use File::Basename;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use List::MoreUtils qw(uniq);
use Bio::Tools::GFF;
use BILS::Handler::GFF3handler qw(:Ok);
use BILS::Handler::GXFhandler qw(:Ok);

my $header = qq{
########################################################
# BILS 2019 - Sweden                                   #  
# jacques.dainat\@nbis.se                               #
# Please cite NBIS (www.nbis.se) when using this tool. #
########################################################
};

my $outfile = undef;
my $gff = undef;
my $add_flag=undef;
my $opt_dist=500;
my $verbose = undef;
my $help= 0;

my @copyARGV=@ARGV;
if ( !GetOptions(
    "help|h" => \$help,
    "gff=s" => \$gff,
    "add_flag|af!" => \$add_flag,
    "d|dist=i" => \$opt_dist,
    "v!" => \$verbose,
    "output|outfile|out|o=s" => \$outfile))

{
    pod2usage( { -message => 'Failed to parse command line',
                 -verbose => 1,
                 -exitval => 1 } );
}

# Print Help and exit
if ($help) {
    pod2usage( { -verbose => 2,
                 -exitval => 2,
                 -message => "$header\n" } );
}
 
if ( ! defined($gff) ){
    pod2usage( {
           -message => "$header\nAt least 1 parameter is mandatory:\nInput reference gff file (--gff)\n\n",
           -verbose => 0,
           -exitval => 1 } );
}

######################
# Manage output file #
my $gffout;
if ($outfile) {
  open(my $fh, '>', $outfile) or die "Could not open file '$outfile' $!";
  $gffout= Bio::Tools::GFF->new(-fh => $fh, -gff_version => 3 );
}
else{
  $gffout = Bio::Tools::GFF->new(-fh => \*STDOUT, -gff_version => 3);
}

                #####################
                #     MAIN          #
                #####################


######################
### Parse GFF input #
my ($omniscient, $hash_mRNAGeneLink) = slurp_gff3_file_JD({ input => $gff
                                                              });
print ("GFF3 file parsed\n");

#counters
my $geneCounter_skip=0;
my $geneCounter_ok=0;
my $total=0;
my @gene_id_ok;

my $sortBySeq = gather_and_sort_l1_location_by_seq_id($omniscient);

foreach my $locusID ( keys %{$sortBySeq}){ # tag_l1 = gene or repeat etc...

  foreach my $tag_l1 ( keys %{$sortBySeq->{$locusID}} ) { 

    # Go through location from left to right ### !!
    while ( @{$sortBySeq->{$locusID}{$tag_l1}} ){
      $total++;

      #location A
      my $location = shift  @{$sortBySeq->{$locusID}{$tag_l1}};# This location will be updated on the fly
      my $id_l1 = $location->[0];
      #print "id_l1 $id_l1\n";

      my $continue = 1;
      my $overlap = 0;
      my $jump = undef;
      #loop to look at potential set of overlaping genes otherwise go through only once
      while ( $continue ){

        # Next location 
        my $location2 = @{$sortBySeq->{$locusID}{$tag_l1}}[0];
        my $id2_l1 = $location2->[0];
        my $dist = $location2->[1] - $location->[2] + 1;
        print "distance $id_l1 - id2_l1 = $dist\n" if ($verbose);
        
        ############################
        #deal with overlap
        if ( ($location->[1] <= $location2->[2]) and ($location->[2] >= $location2->[1])){
             
              if( ! $overlap){

                foreach my $tag_level1 (keys %{$omniscient->{'level1'}}){
                  if (exists_keys($omniscient, ('level1', $tag_level1, lc($id_l1) ) ) ){ 
                    my $level1_feature = $omniscient->{'level1'}{$tag_level1}{lc($id_l1)};
                    add_info($level1_feature, 'O', $verbose);
                  }
                }
              }

              $overlap=1;
                       
              foreach my $tag_level1 (keys %{$omniscient->{'level1'}}){
                if (exists_keys($omniscient, ('level1', $tag_level1, lc($id2_l1) ) ) ){ 
                  my $level1_feature = $omniscient->{'level1'}{$tag_level1}{lc($id2_l1)};
                  add_info($level1_feature, 'O', $verbose);
                }
              }

              if($location2->[2] < $location->[2]){
                my $tothrow = shift  @{$sortBySeq->{$locusID}{$tag_l1}};# Throw location B. We still need to use location A to check the left extremity of the next locus
                                                                          #location A  -------------------------                                --------------------------
                                                                          #location B                ---------
                $total++;
                next;  
              }
              else{
                                                                          # We need to use the location B to check the left extremity of the next locus
                                                                          #location A  -------------------------                                --------------------------
                                                                          #location B                ------------------------
                $jump = 1;
                last;
              }
        
        }
        #
        ############################
        $continue = 0;


        print "after overlap check\n";
        # locus distance is under minimum distance
        if( $dist < $opt_dist)  {
          print "$dist < $opt_dist\n";
                  
          foreach my $tag_level1 (keys %{$omniscient->{'level1'}}){
            if (exists_keys($omniscient, ('level1', $tag_level1, lc($id_l1) ) ) ){ 
              my $level1_feature = $omniscient->{'level1'}{$tag_level1}{lc($id_l1)};            
              add_info($level1_feature, 'R'.$dist, $verbose);
            }
          }

          foreach my $tag_level1 (keys %{$omniscient->{'level1'}}){
            if (exists_keys($omniscient, ('level1', $tag_level1, lc($id2_l1) ) ) ){ 
              my $level1_feature = $omniscient->{'level1'}{$tag_level1}{lc($id2_l1)};  
              add_info($level1_feature, 'L'.$dist, $verbose);
            }
          }
        }

        # distance with next is ok but we have to check what was the result with the previous locus 
        else{
         foreach my $tag_level1 (keys %{$omniscient->{'level1'}}){
            if (exists_keys($omniscient, ('level1', $tag_level1, lc($id_l1) ) ) ){ 
              my $level1_feature = $omniscient->{'level1'}{$tag_level1}{lc($id_l1)};            
              if(! $level1_feature->has_tag('low_dist')){
                $geneCounter_ok ++;
                push @gene_id_ok, lc($id_l1);
              }
            }
          }
        }
      }
    }
  }
}

if($add_flag){
  print_omniscient($omniscient, $gffout); #print result
}
else{
  print_omniscient_from_level1_id_list ($omniscient, \@gene_id_ok, $gffout); #print result
}

#END
my $string_to_print="usage: $0 @copyARGV\n".
  "Results:\n".
  "Total number investigated: $total\n".
  "Number of skipped loci: $geneCounter_skip\n".
  "Number of loci with distance to the surrounding loci over $opt_dist: $geneCounter_ok \n";
print $string_to_print;
print "Bye Bye.\n";
#######################################################################################################################
        ####################
         #     METHODS    #
          ################
           ##############
            ############
             ##########
              ########
               ######
                ####
                 ##


sub add_info{
  my ($feature, $value, $verbose)=@_;

  if($feature->has_tag('low_dist')){
    $feature->add_tag_value('low_dist', $value);
    print $feature->_tag_value('ID')." add $value\n" if ($verbose);
  }
  else{         
    create_or_replace_tag($feature, 'low_dist', $value);
    $geneCounter_skip++;
    print $feature->_tag_value('ID')." create $value\n" if ($verbose);
  }

}
__END__

=head1 NAME

gff3_sp_filter_by_locus_distance.pl -

The script aims to remove or flag loci that are too close to each other. 
Close loci are important to remove when training abinitio tools in order to train intergenic region properly. Indeed if intergenic region (surrouneded part of a locus) contain part of another locus, the training on intergenic part will be biased. 

=head1 SYNOPSIS

    ./gff3_sp_filter_by_locus_distance.pl -gff=infile.gff [ -o outfile ]
    ./gff3_sp_filter_by_locus_distance.pl --help

=head1 OPTIONS

=over 8

=item B<-gff>

Input GFF3 file that will be read

=item B<--dist> or B<-d>

The minimum inter-loci distance to allow.  No default (will not apply
filter by default).

=item B<--add> or B<--add_flag>

Instead of filter the result into two output files, write only one and add the flag <low_dist> in the gff.(tag = Lvalue or tag = Rvalue  where L is left and R right and the value is the distance with accordingle the left or right locus) 

=item B<-o> , B<--output> , B<--out> or B<--outfile>

Output GFF file.  If no output file is specified, the output will be
written to STDOUT.

=item B<-v>

Verbose option, make it easier to follow what is going on for debugging purpose.

=item B<-h> or B<--help>

Display this helpful text.

=back

=cut
