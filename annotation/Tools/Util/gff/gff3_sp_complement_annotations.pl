#!/usr/bin/env perl


use Carp;
use strict;
use Getopt::Long;
use Pod::Usage;
use List::MoreUtils qw(uniq);
use Bio::Tools::GFF;
use BILS::Handler::GFF3handler qw(:Ok);
use BILS::Handler::GXFhandler qw(:Ok);

my $header = qq{
########################################################
# NBIS 2016 - Sweden                                   #  
# jacques.dainat\@nbis.se                               #
# Please cite NBIS (www.nbis.se) when using this tool. #
########################################################
};

my $start_run = time();
my $outfile = undef;
my @opt_files;
my $ref = undef;
my $size_min = 0;
my $help= 0;

# OPTION MANAGMENT
my @copyARGV=@ARGV;
if ( !GetOptions(
    "help|h" => \$help,
    "ref|r|i=s" => \$ref,
    "add|a=s" => \@opt_files,
    "size_min|s=i" => \$size_min,
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

if (! $ref or ! @opt_files ){
    pod2usage( {
           -message => "\nAt least 2 files are mandatory:\n --ref file1 --add file2\n\n",
           -verbose => 0,
           -exitval => 2 } );
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

my ($hash_omniscient, $hash_mRNAGeneLink) = slurp_gff3_file_JD({ input => $ref
                                                              });
print ("$ref GFF3 file parsed\n");
info_omniscient($hash_omniscient);

#Add the features of the other file in the first omniscient. It takes care of name to not have duplicates
foreach my $next_file (@opt_files){
  my ($hash_omniscient2, $hash_mRNAGeneLink2) = slurp_gff3_file_JD({ input => $next_file
                                                              });
  print ("$next_file GFF3 file parsed\n");
  info_omniscient($hash_omniscient2);

  ################################
  # First rename ID to be sure to not add feature with ID already used
  rename_ID_existing_in_omniscient($hash_omniscient, $hash_omniscient2);
  print ("\n$next_file IDs checked and fixed.\n");


  # Quick stat hash before complement
  my %quick_stat1;
  foreach my $level ( ('level1', 'level2') ){
    foreach  my $tag (keys %{$hash_omniscient->{$level}}) {
      my $nb_tag = keys %{$hash_omniscient->{$level}{$tag}};
      $quick_stat1{$level}{$tag} = $nb_tag;
    }
  }

  ####### COMPLEMENT #######
  complement_omniscients($hash_omniscient, $hash_omniscient2, $size_min);
  print ("\nComplement done !\n");


 #RESUME COMPLEMENT
  my $complemented=undef;
  # Quick stat hash after complement
  my %quick_stat2;
  foreach my $level ( ('level1', 'level2') ){
    foreach  my $tag (keys %{$hash_omniscient->{$level}}) {
      my $nb_tag = keys %{$hash_omniscient->{$level}{$tag}};
      $quick_stat2{$level}{$tag} = $nb_tag;
    }
  }

  #About tag from hash1 added which exist in hash2
  foreach my $level ( ('level1', 'level2') ){
    foreach my $tag (keys %{$quick_stat1{$level}}){
      if ($quick_stat1{$level}{$tag} != $quick_stat2{$level}{$tag} ){
        print "We added ".($quick_stat2{$level}{$tag}-$quick_stat1{$level}{$tag})." $tag(s)\n";
        $complemented=1;
      }
    }
  }
  #About tag from hash2 added which dont exist in hash1
  foreach my $level ( ('level1', 'level2') ){
    foreach my $tag (keys %{$quick_stat2{$level}}){
      if (! exists $quick_stat1{$level}{$tag} ){
        print "We added ".$quick_stat2{$level}{$tag}." $tag(s)\n";
        $complemented=1;
      }
    }
  }
  #If nothing added
  if(! $complemented){
    print "\nNothing has been added\n";
  }
  else{
    print "\nNow the data contains:\n";
    info_omniscient($hash_omniscient);
  }
}

########
# Print results
print_omniscient($hash_omniscient, $gffout);  

#END
print "usage: $0 @copyARGV\n";
my $end_run = time();
my $run_time = $end_run - $start_run;
print "Job done in $run_time seconds\n";
__END__

=head1 NAME
 
gff3_sp_complement_annotations.pl - 
This script allow to complement a reference annotation with other annotations.
A l1 feature from the addfile.gff that does not overlap a l1 feature from the reference annotation will be added.
A l1 feature from the addfile.gff without a CDS that overlaps a l1 feature with a CDS from the reference annotation will be added.
A l1 feature from the addfile.gff with a CDS that overlaps a l1 feature without a CDS from the reference annotation will be added. 
A l1 feature from the addfile.gff with a CDS that overlaps a l1 feature with a CDS from the reference annotation will be added only if the CDSs don't overlap.
A l1 feature from the addfile.gff without a CDS that overlaps a l1 feature without a CDS from the reference annotation will be added only if none of the l3 features overlap.
/!\ It is sufficiant that only one isoform is overlapping to prevent the whole gene (l1 feature) from the addfile.gff to be added in the output.


=head1 SYNOPSIS

    ./gff3_sp_complement_annotations.pl --ref annotation_ref.gff --add=addfile1.gff --add=addfile2.gff --out=outFile 
    ./gff3_sp_complement_annotations.pl --help

=head1 OPTIONS

=over 8

=item B<--ref>,  B<-r> or B<-i>

Input GFF3 file(s) used as reference. 

=item B<--add> or B<-a>

Annotation(s) file you would like to use to complement the reference annotation. You can specify as much file you want like so: -a addfile1 -a addfile2 -a addfile3
/!\ The order you provide these files matter. Once the reference file has been complemented by file1, this new annotation becomes the new reference that will be complemented by file2 etc.
/!\ The result with -a addfile1 -a addfile2 will differ to the result from -a addfile2 -a addfile1. So, be aware of what you want if you use several addfiles.

=item  B<--size_min> or B<-s>

Option to keep the non-overlping gene only if the CDS size (in nucleotide) is over the minimum size defined. Default = 0 that means all of them are kept.

=item  B<--out>, B<--output>, B<--outfile> or B<-o>

Output gff3 containing the reference annotation with all the non-overlapping newly added genes from addfiles.gff.

=item B<--help> or B<-h>

Display this helpful text.

=back

=cut
