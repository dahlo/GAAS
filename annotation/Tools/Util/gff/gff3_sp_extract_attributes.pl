#!/usr/bin/env perl


use Carp;
use Clone 'clone';
use strict;
use Getopt::Long;
use Pod::Usage;
use IO::File;
use Data::Dumper;
use List::MoreUtils qw(uniq);
use Bio::Tools::GFF;
use BILS::Handler::GFF3handler qw(:Ok);
use BILS::Handler::GXFhandler qw(:Ok);

my $header = qq{
########################################################
# BILS 2015 - Sweden                                   #  
# jacques.dainat\@nbis.se                               #
# Please cite NBIS (www.nbis.se) when using this tool. #
########################################################
};

my %handlers;
my $gff = undef;
my $one_tsv = undef;
my $help= 0;
my $primaryTag=undef;
my $attributes=undef;
my $outfile=undef;
my $outInOne=undef;
my $doNotReportEmptyCase=undef;

if ( !GetOptions(
    "help|h" => \$help,
    "gff|f=s" => \$gff,
    "d!" => \$doNotReportEmptyCase,
    "m|merge!" => \$one_tsv,
    "p|t|l=s" => \$primaryTag,
    "attributes|a|att=s" => \$attributes,
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
 
if ( ! (defined($gff)) ){
    pod2usage( {
           -message => "$header\nAt least 1 parameter is mandatory:\nInput reference gff file (--gff) \n\n",
           -verbose => 0,
           -exitval => 2 } );
}

# If one output file we can create it here
if($one_tsv){
  if ($outfile) {
    open($outInOne, '>', $outfile) or die "Could not open file $outfile $!";
  }
  else{
    $outInOne->fdopen( fileno(STDOUT), 'w' );
  }
}

# Manage $primaryTag
my @ptagList;
if(! $primaryTag or $primaryTag eq "all"){
  print "We will work on attributes from all features\n";
  push(@ptagList, "all");
}elsif($primaryTag =~/^level[123]$/){
  print "We will work on attributes from all the $primaryTag features\n";
  push(@ptagList, $primaryTag);
}else{
   @ptagList= split(/,/, $primaryTag);
   foreach my $tag (@ptagList){
      if($tag =~/^level[123]$/){
        print "We will work on attributes from all the $tag features\n";
      }
      else{
       print "We will work on attributes from $tag feature.\n";
      }
   }
}

# Manage attributes if given
### If attributes given, parse them:
my @attListOk;
if ($attributes){
  my @attList = split(/,/, $attributes); # split at comma as separated value
  
  foreach my $attribute (@attList){ 
      push @attListOk, $attribute;
      print "$attribute attribute will be processed.\n";

  }
  print "\n";
}


                #####################
                #     MAIN          #
                #####################


######################
### Parse GFF input #
my ($hash_omniscient, $hash_mRNAGeneLink) = slurp_gff3_file_JD({ input => $gff
                                                              });
print ("GFF3 file parsed\n");


foreach my $tag_l1 (keys %{$hash_omniscient->{'level1'}}){
  foreach my $id_l1 (keys %{$hash_omniscient->{'level1'}{$tag_l1}}){
        
    my $feature_l1=$hash_omniscient->{'level1'}{$tag_l1}{$id_l1};
        
    manage_attributes($feature_l1, 'level1', \@ptagList,\@attListOk);

    #################
    # == LEVEL 2 == #
    #################
    foreach my $tag_l2 (keys %{$hash_omniscient->{'level2'}}){ # primary_tag_key_level2 = mrna or mirna or ncrna or trna etc...
      
      if ( exists ($hash_omniscient->{'level2'}{$tag_l2}{$id_l1} ) ){
        foreach my $feature_l2 ( @{$hash_omniscient->{'level2'}{$tag_l2}{$id_l1}}) {
          
          manage_attributes($feature_l2,'level2',, \@ptagList,\@attListOk);
          #################
          # == LEVEL 3 == #
          #################
          my $level2_ID = lc($feature_l2->_tag_value('ID'));

          foreach my $tag_l3 (keys %{$hash_omniscient->{'level3'}}){ # primary_tag_key_level3 = cds or exon or start_codon or utr etc...
            if ( exists ($hash_omniscient->{'level3'}{$tag_l3}{$level2_ID} ) ){
              foreach my $feature_l3 ( @{$hash_omniscient->{'level3'}{$tag_l3}{$level2_ID}}) {
                manage_attributes($feature_l3, 'level3', \@ptagList,\@attListOk);
              }
            }
          }
        }
      }
    }
  }
}
#print "We added $nbNameAdded Name attributes\n";


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

sub  manage_attributes{
  my  ($feature, $level, $ptagList, $attListOk)=@_;

  my $primary_tag=$feature->primary_tag;

  # check primary tag (feature type) to handle
  foreach my $ptag (@$ptagList){

    if($ptag eq "all"){
      tag_from_list($feature,$attListOk);
    }
    elsif(lc($ptag) eq $level){
      tag_from_list($feature,$attListOk);
    }
    elsif(lc($ptag) eq lc($primary_tag) ){
      tag_from_list($feature,$attListOk);
    }
  }
}

sub tag_from_list{
  my  ($feature, $attListOk)=@_;

  my $tags_string = undef;
  foreach my $att ( @{$attListOk} ){
    
    # create handler if needed (on the fly)
    if (! $one_tsv){
      if(! exists ( $handlers{$att} ) ) {
        my $out = IO::File->new();
        if ($outfile) {
          $outfile=~ s/.gff//g;
          open($out, '>', $outfile."_".$att.".txt") or die "Could not open file '$outfile'_'$att.txt' $!";
        }
        else{
          $out->fdopen( fileno(STDOUT), 'w' );
        }
        $handlers{$att}=$out;
      }
    }
        

    if ($feature->has_tag($att)){

      # get values of the attribute
      my @values = $feature->get_tag_values($att);
      
      # print values of one attribute per file
      if (! $one_tsv){
        my $out = $handlers{$att};
        print $out join(",", @values), "\n";
      }
      else{ # put everything in one tsv
        $tags_string .= join(",", @values)."\t";
      }
    }
    else{
      if (! $one_tsv){
        my $out = $handlers{$att};
        print $out ".\n" if (! $doNotReportEmptyCase);
      }
      else{ # put everything in one tsv
        if (! $doNotReportEmptyCase){
          $tags_string .= ".\t";
        }
        else{
          $tags_string .= "\t";
        }
      }
    }
  }
  if($tags_string){
    chop $tags_string;
    print $outInOne  $tags_string."\n";
  }
}


__END__


# while( my $feature = $gffio->next_feature()) {

#     #manage handler
#     my $source_tag = lc($feature->source_tag);    
#     if(! exists ( $handlers{$source_tag} ) ) {

#       open(my $fh, '>', $splitedData_dir."/".$source_tag.".gff") or die "Could not open file '$source_tag' $!";
#       my $gffout= Bio::Tools::GFF->new(-fh => $fh, -gff_version => 3 );
#       $handlers{$source_tag}=$gffout;
#     }

#     my $gffout = $handlers{$source_tag};
#     $gffout->write_feature($feature);
#     }

=head1 NAME

gff3_extract_attributes.pl -
The script take a gff3 file as input. -
The script allows to extract choosen attributes of all or specific feature types. 
The 9th column of a gff/gtf file contains a list of attributes. An attribute (gff3) is like that tag=value

=head1 SYNOPSIS

    ./gff3_extract_attributes.pl -gff file.gff  -att locus_tag,product,name -p level2,cds,exon [ -o outfile ]
    ./gff3_extract_attributes.pl --help

=head1 OPTIONS

=over 8

=item B<--gff> or B<-f>

Input GFF3 file that will be read (and sorted)

=item B<-p>,  B<-t> or  B<-l>

primary tag option, case insensitive, list. Allow to specied the feature types that will be handled. 
You can specified a specific feature by given its primary tag name (column 3) as: cds, Gene, MrNa
You can specify directly all the feature of a particular level: 
      level2=mRNA,ncRNA,tRNA,etc
      level3=CDS,exon,UTR,etc
By default all feature are taking in account. fill the option by the value "all" will have the same behaviour.

=item B<--attributes>, B<--att>, B<-a>

Attributes specified, will be extracted from the feature type specified by the option p (primary tag). List of attributes must be coma separated.
/!\\ You must use "" if name contains spaces.

=item B<--merge> or B<-m>

By default the values of each attribute tag is writen in its dedicated file. To write the values of all tags in only one file use this option.

=item B<-d> 
By default when an attribute is not found for a feature, a dot (.) is reported. If you don't want anything to be printed in such case use this option.

=item B<-o> , B<--output> , B<--out> or B<--outfile>

Output GFF file.  If no output file is specified, the output will be
written to STDOUT.

=item B<-h> or B<--help>

Display this helpful text.

=back

=cut

