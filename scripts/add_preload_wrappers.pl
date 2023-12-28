#!/usr/bin/perl
use strict;

open(IN,"<../zstd/zlibWrapper/zstd_zlibwrapper.c");
my $P;
my $func;
my $args;
my $rtype;
my $nl;
my $nl2;
my $new_line;
my $intermediate_line="";
while(my $orig_line=<IN>)
{
	chomp($orig_line);	
	if($orig_line=~/ZEXTERN (.+) ZEXPORT z_/) 
	{ 
		$rtype = $1;
		$P=1; 

		$new_line=$orig_line; 
		$orig_line=~/\(([^\(\)]+)/;
		my $orig_args = $1;
		my @f=split(/,\s+/,$orig_args); 
		$args = join(", ", @f);
		$args=~s/\s+/ /g;
		
		$new_line=~s/ZEXPORT z_/ZEXPORT /; 
		$new_line=~/ZEXPORT ([^ ]+)\s+OF/; 
		$func=$1; 
		
		my $zf = "zlib_$func";
		$nl = "return z_$func("; 
		$nl2 = "return zlib_$func("; 

		for(my $i=0; $i<scalar(@f);$i++) 
		{ 
			$f[$i]=~s/^.+ ([^ ]+)$/$1/;
			$nl.=", " if($i>0); 
			$nl2.=", " if($i>0); 
			$f[$i]=~s/,\s*$//;
			$f[$i]=~s/\*//g;
			$f[$i]=~s/\)\)/\)/; 
			$nl.=$f[$i]; 
			$nl2.=$f[$i]; 
		} 
		if($orig_line=~/\)\s*$/) 
		{ 
			print "typedef $rtype (*orig_$func)($args);\n";
			print "orig_$func zlib_$func;\n";

			print "$new_line\n"; 
			print "{\n";
			print "\tif(!zlib_$func)\n";
			print "\t{\n";
			print "\t\tzlib_$func = (orig_$func) dlsym(RTLD_NEXT,\"$func\");\n";
			print "\t\t$nl);\n\t}\n"; 
			print "\t$nl2);\n}\n"; 
			$P=undef;
			$nl=undef;
			$nl2=undef;
			$func=undef;
			$args=undef;
			$rtype=undef;
			$new_line=undef;
		} 
		next;
	} 
	if($P) 
	{ 
		$intermediate_line .= $orig_line."\n" if($orig_line!~/\)\s*$/);
		
		my @f=split(/,\s+/,$orig_line); 
		$args .= $orig_line;
		$args=~s/^OF\(\(//;
		$args=~s/\)+//;
		$args=~s/\s+/ /g;
		for(my $i=0; $i<scalar(@f);$i++) 
		{ 
			$f[$i]=~s/^.+ ([^ ]+)$/$1/;
			$f[$i]=~s/,\s*$//;
			$f[$i]=~s/\*//g;
			$f[$i]=~s/\)\)/\)/; 
			$nl.=", ".$f[$i]; 
			$nl2.=", ".$f[$i]; 
		}
		if($orig_line=~/\)\s*$/) 
		{ 
			print "typedef $rtype (*orig_$func)($args);\n";
			print "orig_$func zlib_$func;\n";
			
			print "$new_line\n"; 
			print "$intermediate_line";
			print "$orig_line\n"; 
			print "{\n";
			print "\tif(!zlib_$func)\n";
			print "\t{\n";
			print "\t\tzlib_$func = (orig_$func) dlsym(RTLD_NEXT,\"$func\");\n";
			print "\t\t$nl;\n\t}\n"; 
			print "\t$nl2;\n}\n"; 
			$P=undef;
			$nl=undef;
			$nl2=undef;
			$func=undef;
			$args=undef;
			$rtype=undef;
			$new_line=undef;
			$intermediate_line="";
		} 
	}
}
close(IN);
