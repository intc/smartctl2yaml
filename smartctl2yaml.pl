#!/usr/bin/perl -w

# Created by Antti Antinoja, (C) 2017
# License: gpl-3.0

# tab: 4

use strict;
use warnings;
use Carp;
use YAML;
use Switch;
use JSON;

# === Global variables ========================================================
my $kv={};
my $se={};

# These are the strings we use as "tags" or anchors so that
# our interpreter understands which section of smartctl output
# we are currently dealing with.
my @state_headers=(
	"^=== START OF INFORMATION SECTION",
	"^=== START OF READ SMART DATA SECTION",
	"^General SMART Values:",
	"^Vendor Specific SMART Attributes with Thresholds:",
	"\Q||||||",
	"^Supported Power States",
	"^Supported LBA Sizes",
	"^=== START OF SMART DATA SECTION",
	"^SMART/Health Information",
	"^Error Information"
);

# State / section "Enumeration":
my $st_info=0;
my $st_smart=1;
my $st_general=2;
my $st_vendor=3;
my $st_vs_legend=4;
my $st_pwr_states=5;
my $st_lba_sizes=6;
my $st_smart_data=7;
my $st_smart_health=8;
my $st_error_info=9;

# Section headers:
my $k_info="Information Section";
my $k_smart="SMART Data";
my $k_general="General SMART Values";
my $k_vendor="Vendor Specific Attributes";
my $k_pwr_states="Supported Power States";
my $k_lba_sizes="Supported LBA Sizes";
my $k_smart_health="SMART/Health Information";
my $k_error_info="Error Information";

# Settings:
$se->{"module"}="smartctl2yaml";
$se->{"options"}->{"--outformat"}->{"type"}="array";
$se->{"options"}->{"--outformat"}->{"accept_one"}=["json", "yaml"];
$se->{"options"}->{"--outformat"}->{"value"}="yaml";
$se->{"c_nc"}=      "\e[0m";
$se->{"c_white"}=   "\e[1;37m";
$se->{"c_black"}=   "\e[0;1m";
$se->{"c_blue"}=    "\e[0;34m";
$se->{"c_lblue"}=   "\e[1;34m";
$se->{"c_green"}=   "\e[0;32m";
$se->{"c_lgreen"}=  "\e[1;32m";
$se->{"c_cyan"}=    "\e[0;36m";
$se->{"c_lcyan"}=   "\e[1;36m";
$se->{"c_red"}=     "\e[0;31m";
$se->{"c_lred"}=    "\e[1;31m";
$se->{"c_purple"}=  "\e[0;35m";
$se->{"c_lpurple"}= "\e[1;35m";
$se->{"c_brown"}=   "\e[0;33m";
$se->{"c_yellow"}=  "\e[1;33m";
$se->{"c_gray"}=    "\e[1;30m";
$se->{"c_lgray"}=   "\e[0;37m";

# Modification rules:
my $modify_rules = [
    # Examples:
	#
    #   'replace' on one key path:
    #   ['replace', [key path as array],'search pattern','replace string','g'|'',';']
	#
    #   'replace' on two or more keypaths:
    #   ['replace', [[key path as array],[key path as array]], 'search pattern','replace string','g'|'',';']

    #   Remove all commas from the value
	#   Using array here since the execution order matters.
	['replace', [
			[$k_info, "User Capacity"],
			[$k_info, "Namespace 1 Size/Capacity"],
			[$k_info, "Namespace 1 Utilization"],
			[$k_smart, $k_smart_health, "Data Units Read"],
			[$k_smart, $k_smart_health, "Data Units Written"],
			[$k_smart, $k_smart_health, "Host Read Commands"],
			[$k_smart, $k_smart_health, "Host Write Commands"],
			[$k_smart, $k_smart_health, "Power On Hours"]
		],'\,','','g',';'],

    #   Remove "[any string]" from the value
	['replace', [
			[$k_info, "User Capacity"],
			[$k_info, "Namespace 1 Size/Capacity"],
			[$k_info, "Namespace 1 Utilization"]
		],'.\[.*\]','','',';'],
];

# === Subroutines =============================================================
sub init_kv {
	$kv->{$k_info}={};
	$kv->{$k_info}->{$k_pwr_states}={};
	$kv->{$k_info}->{$k_lba_sizes}={};

	$kv->{$k_smart}={};
	$kv->{$k_smart}->{$k_vendor}={};
	$kv->{$k_smart}->{$k_general}={};
	$kv->{$k_smart}->{$k_smart_health}={};
	$kv->{$k_smart}->{$k_error_info}={};
}

sub check_substr {
	return ($_[0]=~ m/$_[1]/);  # Return 1 if string (2nd parameter) is found
}

sub get_index {
	my ($string,@arr) = @_;
	my $index=0;
	for my $el (@arr) {
		if (check_substr($string,$el)) {
			return $index; }
		$index++;
	}
	return -1;
}

# build_href_if_exists:
# The resulting structure of smartctl output is a hash of hashes.
# This will construct a direct reference to the desired hash and
# it's key and return them both. Parameter $ar_key contains the
# path of keys (first the key's containing hashes and finally the
# key containing the scalar).
sub build_href_if_exists {
	my ($hash,$ar_key)=@_;
	for my $key (@$ar_key){
		if ($hash->{$key}) {
			if ('HASH' eq ref $hash->{$key}) {
				$hash=$hash->{$key};
								# This key is a reference to a hash.
								# Update our location in the hash tree.
			}
			else {
				return $hash, $key;
                                # A scalar key was found. Return reference
								# to it's parent (hash) and the key it self
								# (as a string).
			}
		}
		else {
			#print STDERR "Warning: ", join("->", @$ar_key), " - Key not found.\n" ;
			return;
								# The key was not found. Returns undefined.
		}
	}
}

# print_ah_status:  output debug info.
sub print_ah_status {
	my ($stack, $i, $val,$pop)=@_;
	for (@$stack) { print "\t"; }
	if ($pop) {
		print "<- SURFace\n"; return 0;
	}
	if (!$val) {
		print scalar @$stack,":$i - DIVE ->\n";
		return;
	}
	print scalar @$stack,":$i - val: $val\n";
	return;
}

# array_handler:    Takes action according to the value type inside the array. Calls also surface_handler.
sub array_handler {
	my ($val, $i, $stack, $surface_handler, $pop, $was_scalar)=@_;
	if (ref $val eq 'ARRAY') {
		if (@$val) {            # Array with elements.
			# print_ah_status($stack, $i);
			push(@$stack, $val);
                                # Save this array reference to stack before
                                # entering into it.
			array_walker($val,$stack,$surface_handler);
                                # Enter recursion.
			return;
		}
		else {                  # Empty array.
			if ($pop) {
				# print_ah_status($stack, 0, "", 1);
				my $popped=pop(@$stack);
				if ($was_scalar) {
                                # We'll hand the popped array to the handler
                                # function for furhter prosessing prosessing
                                # IN CASE the previous array elemnt was
                                # a SCALAR.
					$surface_handler->($popped, $i);
				}
				return;
			}
			else {              # Empty array without subarray. Skip it.
				return;
			}
		}
	}
	else {						# $val is not an array.
		# print_ah_status($stack, $i, $val);
		return 1;
	}
}

# array_walker: Walking any array. Works using recursion together with array_handler.
sub array_walker {
	my ($array, $stack, $surface_handler) = @_;
	my $was_scalar=0;
	for (my $i=0;$i<@$array;$i++) {
		my $val=$array->[$i];
		$was_scalar=array_handler($val,$i,$stack, $surface_handler);
	}
	                            # call array_handler with pop flag set
                                # (4th parameter 1) and also let array_handler
                                # to know if the last element was a scalar.
	array_handler([], 0, $stack, $surface_handler, 1, $was_scalar);
}

# sc_replace:  modification rules.
{
	my $c_array=[];
	
    sub sc_replace {
		my ($array,$i,$initial,$me)=@_;
		my $command=0; my $hkeys=1; my $search=2; my $replace=3; my $method=4;
		
		if ($initial){
			if(!$array->[$search]) {
				croak "Error! Search (parameter nr $search) parameter can not be empty!";
			}
			if($array->[$method]){
				if($array->[$method] ne 'g'){
					croak "Error! Unsupported method! (only 'g' is allowed.)";
				}
			}
			if('ARRAY' eq ref $array->[$hkeys]) {
                                # Second element should be an array containing
                                # the key/keys who's values we want to edit.
				$c_array=$array;
                                # Store reference to the original array
				array_handler($array->[$hkeys],$i,[],$me);
                                # Call array_handler which will call this routine
                                # again with each key array so we can do the actual edit.
			}
			else {
				croak "Error! hash key (parameter nr $hkeys) parameter is not of type ARRAY!";
			}
			return;
		}
		
        # Replacing the designated values in the $kv (key-value hash)
		my ($kv_ref, $key)=build_href_if_exists($kv, $array);
		if ($kv_ref) {
			if($c_array->[$method] eq 'g') {
				$kv_ref->{$key} =~ s/$c_array->[$search]/$c_array->[$replace]/g;
			}
			else {
				$kv_ref->{$key} =~ s/$c_array->[$search]/$c_array->[$replace]/;
			}
		}
		return;
	}
}

# cmd_handler: Run sub routine corresponding the command in currnet modification rule.
sub cmd_handler {
	my ($c_array,$i)=@_;
	my $command=$c_array->[0];
	switch ($command) {
		case ("replace") {
			sc_replace($c_array,$i,1,\&sc_replace);
		}
		else {
			croak "Error! $command: Unknown command.\n";
		}
	}
	return;
}

# apply_modification_rules: NON recursive loop for applying each modification rule.
sub apply_modification_rules {
	my ($array) = @_;
	for (my $x=0; $x<scalar(@$array); $x++) {
		cmd_handler($array->[$x],$x)
	}
	return;
}

# add_kv:
sub add_kv {
	my ($section, $lnumber, $txt) = @_;
	(my $key=$txt) =~ s/:.*//;  # Remove everything after the 1st ":" (Filter
                                # out the value).
	(my $val=$txt) =~ s/^.*?://;
                                # Remove everything till the 1st ":" (Filter
                                # out the key).
	$val =~ s/\s+//;            # Remove leading spaces (0x20).
	$key =~ s/\ is$//;          # Remove trailing " is".
	if ($key eq "Device") { return; }
                                # Skip this key
                                # ("Device is:        Not in smartctl database..")
	$section->{ $key } = $val;
	return 0;
}

# add_kv_tabular:
{
    # Local "static" for maintaining data between calls
	my @attributes_legend=();
	my $attributes_count=0;

	sub add_kv_tabular {
		my ($section, $lnumber, $txt, $info_tag, $n, $end_tag) = @_;
		my @info=split(' ', $txt);
                                # Split the line to an array.
		my $elements=scalar @info;
                                # Get number of elements in array.
		if ($info[0] eq $info_tag) {
								# Found info_tag so this is a header line.
                                # Read the header to a global variable for
                                # later use.
			@attributes_legend=@info;
			$attributes_count=scalar @info;
                                # Save the number of elements (global var).
			return;
		}
		if ($end_tag) {
			if ($info[0] eq $end_tag) {
				return 1;		# Reset state
			}
		}
		my $mainkey=$info[$n];
                                # Use n:th element as main key. (starts from 0)
		for(my $x=0;$x<$attributes_count;$x++){
			if ($x!=$n) {		# Assign all keys expect the main key.
				$section->{$mainkey}->{$attributes_legend[$x]}=$info[$x]
			}
		}
		return;
	}
}

# add_multiline_kv:
{
    # Local "static" for maintaining data between calls
	my @keybuffer; my @valbuffer;
	my $key; my $val;
	
	sub add_multiline_kv {
		my ($section, $lnumber, $txt) = @_;
		my $keystring="";
		if ((!$txt)&&($val)) {  # Empty line and we have pending information.
			$section->{$key}=$val;
                                # Save pending information.
			$key=""; $val="";   # Reset
			return 1;           # RETURN and EXIT section.
		}
		if ($txt=~ m/^\S.*$/) { # Line starting with some NON whitespace char -> We have key or part of it
			if ($val) {         # In case $val is populated save the collected key / value data to our hash.
				$section->{$key}=$val;
				$key=""; $val="";
			}
			if ($txt=~ m/\(*\)/) {
                                # Line contains () pair. Key and value present.
				if (@keybuffer) {
                                # We have accumulated key lines without value data.
					 $keystring = "@keybuffer";
                                # "Flatten" keylinedata buffer to $keystring
					 $keystring =~ s/\s$// ;
                                # Remove possible trailing white space character(s).
					 @keybuffer=();
				}
				if ($keystring ne "") {
					$txt="${keystring} ${txt}";
                                # Concatenate possible keystring with current line data.
				}
				($key=$txt) =~ s/:.*//;
                                # Remove everything after the 1st ":" (Filter out the value).
				($val=$txt) =~ s/^.*?://;
                                # Remove everything till the 1st ":" (Filter out the key).
				$val =~ s/\s+//;
                                # Remove leading spaces (0x20).
			} else {            # Key line without value.
				push @keybuffer, $txt;
			}
		} else {                # This is extended value line
			(my $tmp=$txt) =~ s/\s+//;
                                # Remove leading spaces
			$val="$val\n$tmp";  # Concatenate the gathered valuedata (using newline separator).
		}
		return;
	}
}

# parseline:
sub parseline {
	my ($lstate, $lnumber, $txt, $hash) = @_;
	if ($lstate==$st_general) {
		if (add_multiline_kv($hash->{$k_smart}->{$k_general}, $lnumber, $txt)) {
			return -1;				# Reset state
		}
		return $lstate;
	}
	if ($txt) {
		switch ($lstate) {
			case ($st_info) {       # "INFORMATION SECTION".
				add_kv($hash->{$k_info}, $lnumber, $txt);
			}
			case [$st_smart_data, $st_smart] {
									# "SMART DATA".
				add_kv($hash->{$k_smart}, $lnumber, $txt);
			}
			case ($st_vendor) {     # "Vendor Specific SMART Attributes" (Under "SMART DATA").
				add_kv_tabular($hash->{$k_smart}->{$k_vendor}, $lnumber, $txt, "ID#", 1);
			}
			case ($st_vs_legend) {
			}
			case ($st_pwr_states) {
				add_kv_tabular($hash->{$k_info}->{$k_pwr_states}, $lnumber, $txt, "St", 0);
			}
			case ($st_lba_sizes) {
				add_kv_tabular($hash->{$k_info}->{$k_lba_sizes}, $lnumber, $txt, "Id", 0);
			}
			case ($st_smart_health) {
				add_kv($hash->{$k_smart}->{$k_smart_health}, $lnumber, $txt);
			}
			case ($st_error_info) {
				if (add_kv_tabular($hash->{$k_smart}->{$k_error_info},
						$lnumber, $txt, "Num", 0, "...")) {
					return -1;		# Reached end_tag. Reset state.
				}
			}
			else {
				#print STDERR "Unknown section!\n";
			}
		}
		return $lstate;
	}
	return -1;						# No data. Reset state.
}

# smartctl_check:
sub smartctl_check {
	my ($hash) = @_;
	my @firstline=split(/ /, <STDIN>);
	if ($firstline[0] ne "smartctl") {
		print $se->{"c_lred"}, "ERROR! The input stream does not look like smartcl (-x/-a) output - exitting (255)\n";
		exit 255;
	}
	$hash->{"Smartctl"}->{"Version"} = $firstline[1];
}

# show_cli_help_and_exit:
sub show_cli_help_and_exit {
	print $se->{"c_yellow"}, "USAGE:   ", $se->{"c_lgray"},
		"smartctl2yaml.pl [options]\n";
	print "\n";
	print $se->{"c_white"},  "OPTIONS: ", $se->{"c_lgray"},
		"--help, -h\n";
	print "           Show this help.\n";
	print "         --outformat, -o [yaml/json]\n";
	print "           Select output format. (Default: ",
		$se->{"options"}->{"--outformat"}->{"value"}, ")\n";
	exit 1;
}

# conf_check_accept_one:
sub conf_check_accept_one {
	my ($val, $choices)=@_;
	for my $choice (@{ $choices }) {
		if ($val eq $choice) { return 1; }
	}
	return;
}

# conf_handle_array:
sub conf_handle_array {
	my ($opt, $sitem, $val)=@_;
	if (exists $sitem->{"accept_one"}) {
		if ( conf_check_accept_one($val, $sitem->{"accept_one"}) ) {
			$sitem->{"value"}=$val;
		}
		else {                  # Unknown value. Assist & exit.
			print $se->{"c_lred"},  "ERROR:   ", $se->{"c_white"},
				$opt, " ", $se->{"c_lred"}, $val, $se->{"c_lgray"},
				" (Unrecognized value)\n";
			print $se->{"c_lgray"}, "         Value for ", $se->{"c_white"},
				$opt, $se->{"c_lgray"}, " can be ";
			print $se->{"c_lgreen"}, "one", $se->{"c_lgray"},
				" of the following: ";
			print $se->{"c_lgreen"}, join(", ", @{ $sitem->{"accept_one"} }),
				"\n\n";
			show_cli_help_and_exit;
		}
	}
}

# conf_handle_option:
sub conf_handle_option {
	my ($opt,$options,$val)=@_;
	my $sitem = $se->{"options"}->{$opt};
	# Sanity checks:
	my @matches = grep { /$opt/ } @$options;
	if ($#matches!=-1) {      # -1 is the value when no match is found (0 for one!).
		print $se->{"c_lred"},  "ERROR:   ", $se->{"c_lgray"};
			print "Option ", $se->{"c_white"}, $opt, $se->{"c_lgray"}, " has already been set! Please check the command line.\n\n";
		show_cli_help_and_exit;
	}
	if (!$val) {
		print $se->{"c_lred"},  "ERROR:   ", $se->{"c_lgray"};
			print "Option ", $se->{"c_white"}, $opt, $se->{"c_lgray"}, " has been set without a value.\n\n";
		show_cli_help_and_exit;
	}
	switch($sitem->{type}){
		case ("array"){
			conf_handle_array($opt, $sitem, $val);
		}
		else {
			print "Config for", $opt. " has unknown configuration type. Exitting.";
			show_cli_help_and_exit;
		}
	}
	return $opt;
}

# command_line:
sub command_line {
	my $n=$#ARGV+1;
	my $val="";
	my @options=();
	while ($n--) {
		my $x=$ARGV[$n];
		switch ($x) {
			case ["-o", "--outformat"] {
				push(@options, conf_handle_option("--outformat",\@options,$val));
				$val="";
			}
			case ["-h", "--help"] {
				show_cli_help_and_exit;
			}
			else {
				# This is not an option. It's a value or..
				if (!$n) {
					print "Unknown option or a value without option!\n";
					show_cli_help_and_exit;
				}
				$val=$x;
			}
		}
	}
}



# === MAIN ====================================================================       
sub main {
	my $state=-1;
	init_kv;
	command_line;

	# Read the first line of our input for getting version info:
	smartctl_check($kv);

	# State loop. Read input linues and alter the state accordingly.
	for(my $y=1;(my $line = <STDIN>);$y++) {
		chop $line;
		my $state_t = get_index($line,@state_headers);
		if ($state_t != -1) {
			# Line contains a new state header.
			$state=$state_t;
		}
		else {
			# Line is not a state header. Parse the content:
			$state=parseline($state, $y, $line, $kv);
		}
	}

	apply_modification_rules($modify_rules);

	if ($se->{"options"}->{"--outformat"}->{"value"} eq "yaml" ){
		print Dump $kv;
	}
	else {
		print encode_json $kv;
	}
	return;
}

main
