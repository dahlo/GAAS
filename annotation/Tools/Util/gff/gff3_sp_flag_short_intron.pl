#!/usr/bin/env perl

use strict;
use warnings;
use POSIX qw(strftime);
use File::Basename;
use Carp;
use Getopt::Long;
use IO::File;
use Pod::Usage;
use BILS::Handler::GXFhandler qw(:Ok);
use BILS::Handler::GFF3handler qw(:Ok);
use Bio::Tools::GFF;
use BILS::GFF3::Statistics qw(:Ok);

my $header = qq{
########################################################
# NBIS 2019 - Sweden                                   #  
# jacques.dainat\@nbis.se                               #
# Please cite NBIS (www.nbis.se) when using this tool. #
########################################################
};


my $opt_file;
my $opt_output=undef;
my $verbose=undef;
my $Xsize=10;
my $opt_help = 0;

my @copyARGV=@ARGV;
if ( !GetOptions( 'f|gff|ref|reffile=s' => \$opt_file,
                  'o|out|output=s' => \$opt_output,
                  'v|verbose!'      => \$verbose,
                  'i|intron_size=i'      => \$Xsize,
                  'h|help!'         => \$opt_help ) )
{
    pod2usage( { -message => 'Failed to parse command line',
                 -verbose => 1,
                 -exitval => 1 } );
}

if ($opt_help) {
    pod2usage( { -verbose => 2,
                 -exitval => 2,
                 -message => "$header\n" } );
}
if ( ! defined($opt_file) ) {
    pod2usage( {
           -message => "$header\nMust specify at least 1 parameters:\nReference data gff3 file (--gff)\n",
           -verbose => 0,
           -exitval => 1 } );
}

# #######################
# # START Manage Option #
# #######################
my $gffout;
my $ostreamReport;
if (defined($opt_output) ) {
  my ($filename,$path,$ext) = fileparse($opt_output,qr/\.[^.]*/);
  $ostreamReport=IO::File->new(">".$path.$filename."_report.txt" ) or croak( sprintf( "Can not open '%s' for writing %s", $filename."_report.txt", $! ));

  open(my $fh, '>', $opt_output) or die "Could not open file $opt_output $!";
  $gffout= Bio::Tools::GFF->new(-fh => $fh, -gff_version => 3 );
}
else{
  $ostreamReport = \*STDOUT or die ( sprintf( "Can not open '%s' for writing %s", "STDOUT", $! ));
  $gffout = Bio::Tools::GFF->new(-fh => \*STDOUT, -gff_version => 3);
}
my $string1 = strftime "%m/%d/%Y at %Hh%Mm%Ss", localtime;
$string1 .= "\n\nusage: $0 @copyARGV\n\n";

print $ostreamReport $string1;
if($opt_output){print $string1;}

                                                      #######################
                                                      #        MAIN         #
#                     >>>>>>>>>>>>>>>>>>>>>>>>>       #######################       <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

######################
### Parse GFF input #
print "Reading ".$opt_file,"\n";
my ($hash_omniscient, $hash_mRNAGeneLink) = slurp_gff3_file_JD({ input => $opt_file
                                                              });
print("Parsing Finished\n\n");
### END Parse GFF input #
#########################

my $nb_cases=0;
my $tag = "pseudo";
######################
### Parse GFF input #
foreach my $tag_l1 (keys %{$hash_omniscient->{'level1'}}){
  foreach my $id_l1 (keys %{$hash_omniscient->{'level1'}{$tag_l1}}){
    my $shortest_intron=10000000000;
    foreach my $tag_l2 (keys %{$hash_omniscient->{'level2'}}){
      if (exists_keys($hash_omniscient,('level2',$tag_l2,$id_l1) ) ){
        # #MATCH CASE - We ahve to count the L2 match features
        # if($tag_l2 =~ "match"){
        #   my $counterL2_match=-1;
        #   foreach my $feature_l2 (@{$hash_omniscient->{'level2'}{$tag_l2}{$id_l1}}){
      
        #     my @sortedList = sort {$a->start <=> $b->start} @{$hash_omniscient->{'level2'}{$tag_l2}{$id_l1}};
        #     my $indexLastL2 = $#{$hash_omniscient->{'level2'}{$tag_l2}{$id_l1}};
        #     $counterL2_match++;

        #     if($counterL2_match > 0 and $counterL2_match <= $indexLastL2){
        #       my $intronSize = $sortedList[$counterL2_match]->start - $sortedList[$counterL2_match-1]->end;
        #       $shortest_intron = $intronSize if($intronSize < $shortest_intron)
        #     }
        #   }
        # }
        # else{
          foreach my $feature_l2 (@{$hash_omniscient->{'level2'}{$tag_l2}{$id_l1}}){
            my $level2_ID = lc($feature_l2->_tag_value('ID'));
          
            # if ( exists_keys($hash_omniscient,('level3','exon',$level2_ID) ) ){
            #   my $counterL3=-1;
            #   my $indexLast = $#{$hash_omniscient->{'level3'}{'exon'}{$level2_ID}};      
            #   my @sortedList = sort {$a->start <=> $b->start} @{$hash_omniscient->{'level3'}{'exon'}{$level2_ID}};         
            #   foreach my $feature_l3 ( @sortedList ){
            #     #count number feature of tag_l3 type
            #     $counterL3++;
            #     #Manage Introns## from the second intron to the last (from index 1 to last index of the table sortedList) ## We go inside this loop only if we have more than 1 feature.
            #     if($counterL3 > 0 and $counterL3 <= $indexLast){
            #       my $intronSize = $sortedList[$counterL3]->start - $sortedList[$counterL3-1]->end;
            #       $shortest_intron = $intronSize if($intronSize < $shortest_intron)
            #     }
            #   }
            # }
            # else{
              if ( exists_keys($hash_omniscient,('level3','cds',$level2_ID)) ){
                my $counterL3=-1;
                my $indexLast = $#{$hash_omniscient->{'level3'}{'cds'}{$level2_ID}};      
                my @sortedList = sort {$a->start <=> $b->start} @{$hash_omniscient->{'level3'}{'cds'}{$level2_ID}};         
                foreach my $feature_l3 ( @sortedList ){
                  #count number feature of tag_l3 type
                  $counterL3++;
                  #Manage Introns## from the second intron to the last (from index 1 to last index of the table sortedList) ## We go inside this loop only if we have more than 1 feature.
                  if($counterL3 > 0 and $counterL3 <= $indexLast){
                    my $intronSize = $sortedList[$counterL3]->start - $sortedList[$counterL3-1]->end;
                    $shortest_intron = $intronSize if($intronSize < $shortest_intron)
                  }
                }
              }
              # foreach my $tag_l3 (keys %{$hash_omniscient->{'level3'}}){
              #   if (index(lc($tag_l3), 'utr') != -1) {
              #     if ( exists_keys($hash_omniscient,('level3',$tag_l3,$level2_ID)) ){
              #       my $counterL3=-1;
              #       my $indexLast = $#{$hash_omniscient->{'level3'}{$tag_l3}{$level2_ID}};      
              #       my @sortedList = sort {$a->start <=> $b->start} @{$hash_omniscient->{'level3'}{$tag_l3}{$level2_ID}};         
              #       foreach my $feature_l3 ( @sortedList ){
              #         #count number feature of tag_l3 type
              #         $counterL3++;
              #         #Manage Introns## from the second intron to the last (from index 1 to last index of the table sortedList) ## We go inside this loop only if we have more than 1 feature.
              #         if($counterL3 > 0 and $counterL3 <= $indexLast){
              #           my $intronSize = $sortedList[$counterL3]->start - $sortedList[$counterL3-1]->end;
              #           $shortest_intron = $intronSize if($intronSize < $shortest_intron)
              #         }
              #       }
              #     }
              #   }
              # }
            #}
          #}
        }
      }
    }
    print "Shortest intron for $id_l1:".$shortest_intron."\n" if($shortest_intron != 10000000000 and $verbose);
    if ($shortest_intron < $Xsize){ 
      print "flag the gene $id_l1\n";
      $nb_cases++;
          
      my $feature_l1 = $hash_omniscient->{'level1'}{$tag_l1}{$id_l1};
      $feature_l1->add_tag_value($tag, $shortest_intron);
      if($feature_l1->has_tag('product') ){
        $feature_l1->add_tag_value('note', $feature_l1->get_tag_values('product'));
        $feature_l1->remove_tag('product');
      }
      foreach my $tag_l2 (keys %{$hash_omniscient->{'level2'}}){
        if (exists_keys ($hash_omniscient, ('level2', $tag_l2, $id_l1) ) ) {
          foreach my $feature_l2 (@{$hash_omniscient->{'level2'}{$tag_l2}{$id_l1}}){
            my $level2_ID = lc($feature_l2->_tag_value('ID'));
            $feature_l2->add_tag_value($tag, $shortest_intron);
            if($feature_l2->has_tag('product') ){
              $feature_l2->add_tag_value('note', $feature_l2->get_tag_values('product'));
              $feature_l2->remove_tag('product');
            }

            foreach my $tag_l3 (keys %{$hash_omniscient->{'level3'}}){
              if ( exists_keys($hash_omniscient, ('level3', $tag_l3, $level2_ID) ) ){
                foreach my $feature_l3 (@{$hash_omniscient->{'level3'}{$tag_l3}{$level2_ID}}){
                  $feature_l3->add_tag_value($tag, $shortest_intron);
                  if($feature_l3->has_tag('product') ){
                    $feature_l3->add_tag_value('note', $feature_l3->get_tag_values('product'));
                    $feature_l3->remove_tag('product');
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

my $toprint = "We found $nb_cases cases where introns were < $Xsize, we flagged them with the attribute $tag. The value of this tag is size of the shortest intron found in this gene.\n";
print $ostreamReport $toprint;
if($opt_output){print $toprint;}
print_omniscient($hash_omniscient, $gffout); #print gene modified
      ######################### 
      ######### END ###########
      #########################


#######################################################################################################################
        ####################
         #     methods    #
          ################
           ##############
            ############
             ##########
              ########
               ######
                ####
                 ##



__END__


=head1 NAME
 
gff3_sp_flag_short_introns.pl - This script will flag the short introns with the attribute pseudo. Is is usefull to avoid ERROR when submiting the 
data to EBI. (Typical EBI error message: ********ERROR: Intron usually expected to be at least 10 nt long. Please check the accuracy)

=head1 SYNOPSIS

    ./gff3_sp_flag_short_introns.pl --gff infile --out outFile 
    ./gff3_sp_flag_short_introns.pl --help

=head1 OPTIONS

=over 8

=item B<--gff>, B<-f>, B<--ref> or B<-reffile>

Input GFF3 file correponding to gene build.

=item  B<--intron_size> or B<-i>

Minimum intron size, default 10. All genes with an intron < of this size will be flagged with the pseudo attribute (the value will be the size of the smallest intron found within the incriminated gene)

=item  B<--out>, B<--output> or B<-o>

Output gff3 file where the result will be printed.

=item B<-v>

Bolean. Verbose for debugging purpose.

=item B<--help> or B<-h>

Display this helpful text.

=back

=cut
