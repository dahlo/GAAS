#!/usr/bin/env perl

use strict;
use File::Copy;
use warnings;
use Scalar::Util qw(openhandle);
use Time::Piece;
use Time::Seconds;
use Cwd;
use Pod::Usage;
use URI::Escape;
use Getopt::Long qw(:config no_ignore_case bundling);
use BILS::Handler::GXFhandler qw(:Ok);
use BILS::Handler::GFF3handler qw(:Ok);
use Bio::Tools::GFF;
use IO::File;
use File::Basename;
use IPC::Cmd qw[can_run run];

my $header = qq{
########################################################
# NBIS 2015 - Sweden                                   #  
# jacques.dainat\@nbis.se                               #
# Please cite NBIS (www.nbis.se) when using this tool. #
########################################################
};

my $output = undef;
my $in = undef;
my $help= 0;

if ( !GetOptions(
    "help|h" => \$help,
    "i=s" => \$in,
    "output|out|o=s" => \$output))

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

#######################
### MANAGE OPTIONS ####
#######################

# MANAGE IN
my @inDir;
my $dir = getcwd;

if(! $in){
	# Find the datastore index
	my $maker_dir = undef;

	opendir(DIR, $dir) or die "couldn't open $dir: $!\n";
	my @dirList = readdir DIR;
	closedir DIR;

	my (@matchedDir) = grep $_ =~ /^.*\.maker\.output$/ , @dirList ;

	foreach my $makerDir (@matchedDir){
		push(@inDir, $makerDir);
	}
}
else{
	if (! -d "$in") {
		die "The outdirectory $in doesn't exist.\n";
	}
	else{
		push(@inDir, $in);
	}
} 

# MESSAGES
my $nbDir=$#inDir+1; 
if ($nbDir == 0){die "There seems to be no maker output directory here, exiting...\n";}            
print "We found $nbDir maker output directorie(s):\n";
foreach my $makerDir (@inDir){
		print "\t+$makerDir\n";
}	

#CONSTANT
my $maker_annotation_prefix = "maker_annotation";
my $maker_mix_prefix = "maker_mix";

                #####################
                #     MAIN          #
                #####################

#############################
# Read the genome_datastore #
#############################
foreach my $makerDir (@inDir){
	print "\nDealing with $makerDir:\n";
	my %file_hds;
	my $genomeName = $makerDir;
	$genomeName =~ s/\.maker\.output.*//;
	my $maker_dir_path = $dir . "/" . $makerDir."/";
	my $datastore = $maker_dir_path.$genomeName."_datastore" ;

# --------------- check presence datastore ----------------------
	if (-d $datastore ) {
        	print "Datastore folder found in $makerDir, merging annotations now...\n";
	} else {
	        die "Could not find datastore index ($datastore), exiting...\n";
	}
# --------------- check output folder ----------------------
	
	my $outfolder = undef;
	if ($output){
		if ($nbDir == 1){
			$outfolder = $output;
		}
		else{
			$outfolder = $output."_$genomeName";
		}
	}
	else{ $outfolder = "maker_output_processed_$genomeName";}
	if (-d "$outfolder") {
		print "The output directory <$outfolder> already exists, let's see if something is missing inside.\n";
	} 
	else{
		print "Creating the $outfolder folder\n";
		mkdir $outfolder;
	}

# --------------- GATHERING gff and fasta ----------------------
	if ( ( grep -f, glob "$outfolder/*.fasta") or ( grep -f, glob "$outfolder/*.gff") ){
		print "Output fasta/gff file already exists. We skip the gathering step.\n";
	}
	else{
		print "Now collecting gff and fasta files...\n";
		collect_recursive(\%file_hds, $datastore, $outfolder, $genomeName);

		#Close all file_handler opened
		foreach my $key (keys %file_hds){
			close $file_hds{$key};
		}
	}


	#-------------------------------------------------Save maker option files-------------------------------------------------
	print "Now save a copy of the Maker option files ...\n";
	if (-f "$outfolder/maker_opts.ctl") {
		print "A copy of the Maker files already exists in $outfolder/maker_opts.ctl.  We skip it.\n";
	}
	else{
		if(! $in){
			copy("maker_opts.ctl","$outfolder/maker_opts.ctl") or print "Copy failed: $! $outfolder/maker_opts.ctl\n";
			copy("maker_exe.ctl","$outfolder/maker_exe.ctl") or print "Copy failed: $! $outfolder/maker_exe.ctl\n";
			copy("maker_evm.ctl","$outfolder/maker_evm.ctl") or print "Copy failed: $! $outfolder/maker_evm.ctl\n";
			copy("maker_bopts.ctl","$outfolder/maker_bopts.ctl") or print "Copy failed: $! $outfolder/maker_bopts.ctl\n";
		}
		else{
			my ($name,$path,$suffix) = fileparse($in);
			copy("$path/maker_opts.ctl","$outfolder/maker_opts.ctl") or print  "Copy failed: $! $outfolder/maker_opts.ctl\n";
			copy("$path/maker_exe.ctl","$outfolder/maker_exe.ctl") or print "Copy failed: $! $outfolder/maker_exe.ctl\n";
			copy("$path/maker_evm.ctl","$outfolder/maker_evm.ctl") or print "Copy failed: $! $outfolder/maker_evm.ctl\n";
			copy("$path/maker_bopts.ctl","$outfolder/maker_bopts.ctl") or print "Copy failed: $! $outfolder/maker_bopts.ctl\n";
		}
	}


	############################################
	# Now manage to split file by kind of data # Split is done on the fly (no data saved in memory)
	############################################
	print "Now protecting the maker_annotation.gff annotation by making it readable only...\n";
	#make the annotation safe
	my $annotation="$outfolder/maker_annotation.gff";
	if (-f $annotation) {		
		system "chmod 444 $annotation";
	}
	else{
		print "ERROR: Do not find the $annotation file !\n";
	}


	#do statistics
	my $annotation_stat="$outfolder/maker_annotation_stat.txt";
	if (-f $annotation_stat) {	
		print "$annotation_stat file already exsits...\n";
	}
	else{
		print "Now performing the statistics of the annotation file $annotation...\n";
		my $full_path = can_run('gff3_sp_statistics.pl') or print "Cannot launch statistics. gff3_sp_statistics.pl script not available\n";
		if ($full_path) {	
		        system "gff3_sp_statistics.pl --gff $annotation -o $annotation_stat > $outfolder/maker_annotation_parsing.log";
		}
	}
	print "All done!\n";
}

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

sub collect_recursive {
    my ($file_hds, $full_path, $out, $genomeName) = @_;
	
	my ($name,$path,$suffix) = fileparse($full_path,qr/\.[^.]*/);

    if( ! -d $full_path ){
    	
    	###################
    	# deal with fasta #
    	if($suffix eq ".fasta"){
    		my $key = undef;
    		my $type = undef;
    		if($name =~ /([^\.]+)\.transcripts/){
    			$key = $1;
    			$type = "transcripts";
    		}
    		if($name =~ /([^\.]+)\.proteins/){
    			$key = $1;
    			$type = "proteins";
    		}
    		if($name =~ /([^\.]+)\.noncoding/){
    			$key = $1;
    			$type = "noncoding";
    		}
    		if($key){
    			my $prot_out_file_name=undef;
    			if ($key eq 'maker'){ # protein or transcript correspinding to the maker annotation 
					$prot_out_file_name = "$maker_annotation_prefix.$type.fasta";
    			}
    			else{
    				my $source = "maker.$key";
    				$prot_out_file_name = "$genomeName.all.$source.$type.fasta";
    			}

				my $protein_out_fh=undef;
				if( _exists_keys ($file_hds,($prot_out_file_name)) ){
					$protein_out_fh = $file_hds->{$prot_out_file_name};
				}
				else{
					open($protein_out_fh, '>', "$out/$prot_out_file_name") or die "Could not open file '$out/$prot_out_file_name' $!";
					$file_hds->{$prot_out_file_name}=$protein_out_fh;
				}
				 	
	    		#print
	    		open(my $fh, '<:encoding(UTF-8)', $full_path) or die "Could not open file '$full_path' $!";
					while (<$fh>) {
						print $protein_out_fh $_;
					}
				close $fh;
    		}
    	}

    	################
 		#deal with gff #
    	if($suffix eq ".gff"){
    		system "cat $full_path >> $out/$maker_mix_prefix.gff";
			system "awk '{if(\$2 ~ /[a-zA-Z]+/) if(\$2==\"maker\") { print \$0 >> \"$out/$maker_annotation_prefix.gff\" } else { gsub(/:/, \"_\" ,\$2); print \$0 >> \"$out/\"\$2\".gff\" } }' $full_path";
    	}
    	
    	return;
    }
    if($name =~ /^theVoid/){ # In the void there is sub results already stored in the up folder. No need to go such deep otherwise we will have duplicates.
    	return;
    }
    opendir my $dh, $full_path or die;
    while (my $sub = readdir $dh) {
        next if $sub eq '.' or $sub eq '..';
 
        collect_recursive($file_hds, "$full_path/$sub", $out, $genomeName);
    }
    close $dh;
    return;
}

sub _exists_keys {
    my ($hash, $key, @keys) = @_;

    if (ref $hash eq 'HASH' && exists $hash->{$key}) {
        if (@keys) {
            return exists_keys($hash->{$key}, @keys);
        }
        return 1;
    }
    return '';
}

__END__
# --------------



=head1 NAME

maker_merge_outputs_from datastore.pl - The script will look over the datastore folder and subfolders to gather all outputs.

=head1 SYNOPSIS

    ./maker_merge_outputs_from.pl 
    ./maker_merge_outputs_from.pl --help

=head1 OPTIONS

=over 8

=item B<-i>

The path to the input directory. If none given, we assume that the script is launched where Maker was run. So, in that case the script will look for the folder 
*.maker.output.

=item B<-o> or B<--output>

The name of the output directory. By default the name is annotations

=item B<-h> or B<--help>

Display this helpful text.

=back

=cut
