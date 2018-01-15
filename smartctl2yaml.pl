#!/usr/bin/perl -w
#
# Created by Antti Antinoja, (C) 2017, 2018
# License: gpl-3.0
#
# tab: 2
#
#
use strict;
use warnings;
use YAML;
use Switch;
# use JSON;
#
# Global varables:
my $keyvaluehash={};
#
#
my @states=(                              # One can use regular expressions here.
  "^=== START OF INFORMATION SECTION",
  "^=== START OF READ SMART DATA SECTION",
  "^General SMART Values:",
  "^Vendor Specific SMART Attributes with Thresholds:",
  "\Q||||||",
);
#
# State / section "Enumeration":
my $st_info=0;
my $st_smart=1;
my $st_general=2;
my $st_vendor=3;
my $st_vs_legend=4;
#
# Section headers:
my $k_info="Information Section";
my $k_smart="SMART Data";
my $k_general="General SMART Values";
my $k_vendor="Vendor Specific Attributes";
#
# Subroutines:
sub check_substr {
  return ($_[0]=~ m/$_[1]/);              # Return 1 if string (2nd parameter) is found.
}
#
#
sub get_index {
  my ($string,@arr) = @_;
  my $index=0;
  for my $el (@arr) {
    if (check_substr($string,$el)) {
      return $index; }                    # Return elements index number. Index will define the state of the parser.
    $index++;
  }
  return -1;                              # Return -1 in case the arrayelement was not found from $string.
}
#
#
my $modify_script = [
# examples:
# 'replace' with one key path:
# ['replace', [hash key's (comma separated)],'search pattern','replace string','g'|'',';']
# 'replace' with two or more keypaths: 
# ['replace', [[hash key's (comma separated)],[hash key's (comma separated)]]'search pattern','replace string','g'|'',';']
  ['replace', [$k_info, "User Capacity"],'\,','','g',';'],      # remove all commas from the value
  ['replace', [$k_info, "User Capacity"],'.\[.*\]','','',';'],  # remove "[any string]" from the value
  ['End']
];
#
#
sub build_href_if_exists {
  my ($hash,$ar_key)=@_;
  for my $key (@$ar_key){
    if ($hash->{$key}) {
      if ('HASH' eq ref $hash->{$key}) {
        $hash=$hash->{$key};
      }
      else {
        return ($hash, $key);                     # Return the second last key and the name of the 
                                                  # last key as string. I tired returning the reference to the
                                                  # last key but it returns the value insted if referense to
                                                  # the hash. =(
      }
    }
    else {
      print "Error! - key: $key was not found!";
      return {};
    }
  }
  return $hash;
}
#
# print_ah_status: output some debug info..
sub print_ah_status {
  my ($stack, $i, $val,$pop)=@_;
  for (@$stack) { print "\t"; }
  if ($pop) { 
    print "<- SURFace\n"; return 0;
  }
  if (!$val) {
    print scalar @$stack,":$i - DIVE ->\n";
    return 0;
  }
  print scalar @$stack,":$i - val: $val\n";
}
#
# array_handler: Takes action according to the value type inside the array. Calls also surface_handler.
sub array_handler {
  my ($val, $i, $stack, $surface_handler, $pop, $was_scalar)=@_;
  if (ref $val eq 'ARRAY') {
    if (@$val) {                                    # $val is an array with elements.
      #print_ah_status($stack, $i);
      push(@$stack, $val);                          # Save this array reference to stack before entering into it.
      array_walker($val,$stack,$surface_handler);   # Enter recursion!
      return 0;
    }
    else {                                          # $val is an empty array.
      if ($pop) {                                   # Pop flag is on => pop the stack! (array_walker has exitted an subarray)
        #print_ah_status($stack, 0, "", 1);
        my $popped=pop(@$stack);                    # We'll hand the popped array to the handler function for
        if ($was_scalar) {                          # furhter prosessing IN CASE the previous array elemnt was
          $surface_handler->($popped, $i);          # a SCALAR (-> Last element in popped contains scalar value).
        }
        return 0;
      }
      else {                                        # Empty array. Skip it!
        return 0;
      }
    }
  }
  else {
    #print_ah_status($stack, $i, $val);
    return 1;
  }
}
#
# array_walker: Walking any array. Works using recursion together with array_handler.
sub array_walker {
  my ($array, $stack, $surface_handler) = @_;
  my $was_scalar=0;
  for (my $i=0;$i<@$array;$i++) {
    my $val=$array->[$i];
    $was_scalar=array_handler($val,$i,$stack, $surface_handler);
  }
  # call array_handler with pop flag set (4th parameter 1) and also
  # let array_handler to know if the last element was a scalar.
  array_handler([], 0, $stack, $surface_handler, 1, $was_scalar); 
}
#
# sc_replace: The functions required for performing "replace" command (modify script).
{
  my $c_array=[];
  #
  #
  sub sc_replace {
    my ($array,$i,$initial,$me)=@_;
    my $command=0; my $hkeys=1; my $search=2; my $replace=3; my $method=4;
    #
    # replace command: Entry checks and call for array_handler.
    if ($initial){
      if(!$array->[$search]) {
        print "Error! $search:nd parameter can not be empty!";
        return 1;
      }
      if($array->[$method]){
        if($array->[$method] ne 'g'){
          print "Error! Unsupported method! (only 'g' is allowed.)\n";
          return 1;
        }
      }
      if('ARRAY' eq ref $array->[$hkeys]) {         # Second element should be an array containing
                                                    # the key/keys who's values we want to edit.
        $c_array=$array;                            # Store reference to the original array in $c_array.
        array_handler($array->[$hkeys],$i,[],$me);  # Call array_handler which will call this routine
        return 0;                                   # again with each key array so we can do the actual edit.
      }
      else {
        print "Error! $hkeys:st parameter is not of type ARRAY!\n";
        return 1;
      }
    }
    #
    # Replacing the designated values in the $keyvaluhash:
    my ($kv_ref, $key)=build_href_if_exists($keyvaluehash, $array);
    if($c_array->[$method] eq 'g') {
      $kv_ref->{$key} =~ s/$c_array->[$search]/$c_array->[$replace]/g;
    }
    else {
      $kv_ref->{$key} =~ s/$c_array->[$search]/$c_array->[$replace]/;
    }
    return 0;
  }
}
#
# cmd_handler: Select the sub routine corresponding the command in modification script.
sub cmd_handler {
  my ($c_array,$i)=@_;
  my $command=$c_array->[0];
  switch ($command) {
    case ("replace") {
      if (sc_replace($c_array,$i,1,\&sc_replace)) { 
        print "Error! Failed command: replace\n";
        return 1;
      }
    }
    case ("End") {
      return 0;
    }
    else {
      print "Error! $command: Unknown command.\n";
      return 1;
    }
  }
}
#
# cmd_loop: NON recursive loop for itereating each command in the value modification script.
sub cmd_loop {
  my ($array) = @_;
  for (my $x=0; $x<scalar(@$array); $x++) {
    if (cmd_handler($array->[$x],$x)) {
      print "Error! Exitting cmd_loop.\n";
      return 1;
    }
  }
  return 0;
}
#
#
sub add_kv {
  my ($section, $lnumber, $txt) = @_;
  (my $key=$txt) =~ s/:.*//;              # Remove everything after the 1st ":" (Filter out the value).
  (my $val=$txt) =~ s/^.*?://;            # Remove everything till the 1st ":" (Filter out the key).
  $val =~ s/\s+//;                        # Remove leading spaces (0x20).
  $key =~ s/\ is$//;                      # Remove trailing " is".
  if ($key eq "Device") { return; }       # Skip this key ("Device is:        Not in smartctl database..")
  $section->{ $key } = $val;
  return 0;
}
#
#
{
  my @attributes_legend=();               # Local "static" for maintaining data between calls.
  my $attributes_count=0;                 # --""--
  #
  #
  sub add_kv_tabular {
    my ($section, $lnumber, $txt) = @_;
    my @info=split(' ', $txt);            # Split the line to an array.
    my $elements=scalar @info;            # Get number of elements in array.
    if ($info[0] eq "ID#") {              # In the case of the "header" line:
      @attributes_legend=@info;           # * Read the header to a global variable for later use.
      $attributes_count=scalar @info;     # * Save the number of elements to another global var.
      return 0;                           # * RETURN and do not save things to $keyvaluhash.
    }
    my $mainkey=""; $mainkey=$info[1];    # Use 2nd element as mainkey.
    $section->{$mainkey}->{"ID"}=$info[0];  # Add 1st element..
    for(my $n=2;$n<$attributes_count;$n++){ # .. and the rest.
      $section->{$mainkey}->{$attributes_legend[$n]}=$info[$n]
    }
    return 0;
  }
}

{
  my @keybuffer; my @valbuffer;           # Local "static" for maintaining data between calls.
  my $key; my $val;                       # --""--
  #
  #
  sub add_multiline_kv {
    my ($section, $lnumber, $txt) = @_;
    my $keystring="";
    if ((!$txt)&&($val)) {                # Empty line and we have pending information.
      $section->{$key}=$val;              # Save pending information.
      $key=""; $val="";                   # Resetting.
      return 1;                           # RETURN and EXIT section.
    }
    if ($txt=~ m/^\S.*$/) {               # Line starting with some NON whitespace char -> We have key or part of it
      if ($val) {                         # In case $val is populated save the collected key / value data to our hash.
        $section->{$key}=$val;            # Update $keyvaluehash;
        $key=""; $val="";                 # Resetting.
      }
      if ($txt=~ m/\(*\)/) {              # Line has () pair. Key and value present.
        if (@keybuffer) {                 # So we have accumulated key lines without value data..
           $keystring = "@keybuffer";     # .. Flatten keylinedata buffer to $keystring.
           $keystring =~ s/\s$// ;        # Remove possible trailing white space character(s).
           @keybuffer=();                 # Reset buffer.
        }
        if ($keystring ne "") {
          $txt="${keystring} ${txt}";     # Concatenate possible keystring with current line data.
        }
        ($key=$txt) =~ s/:.*//;           # Remove everything after the 1st ":" (Filter out the value).
        ($val=$txt) =~ s/^.*?://;         # Remove everything till the 1st ":" (Filter out the key).
        $val =~ s/\s+//;                  # Remove leading spaces (0x20).
      } else {                            # Key line without value.
        push @keybuffer, $txt;
      }
    } else {                              # This is extended value line
      (my $tmp=$txt) =~ s/\s+//;          # Remove leading spaces
      $val="$val\n$tmp";                  # Concatenate the gathered valuedata (using newline separator).
    }
    return 0;
  }
}
#
#
sub parseline {
  my ($lstate, $lnumber, $txt, $hash) = @_;
  switch ($lstate) {
    case ($st_info) {                     # Handle "INFORMATION SECTION".
      if (!$txt) {return -1;}             # In case of an empty line we return to default state (-1).
      add_kv($hash->{$k_info}, $lnumber, $txt);
    }
    case ($st_smart) {                    # Handle 1st key under "SMART DATA".
      if (!$txt) {return -1;}
      add_kv($hash->{$k_smart}, $lnumber, $txt);
    }
    case ($st_general) {                  # Handle "Genereal SMART values" (Under "SMART DATA").
      if (add_multiline_kv($hash->{$k_smart}->{$k_general}, $lnumber, $txt)) {
        return -1;
      }
    }
    case ($st_vendor) {                   # Handle "Vendor Specific SMART Attributes" (Under "SMART DATA").
      if (!$txt) {return -1;}
      add_kv_tabular($hash->{$k_smart}->{$k_vendor}, $lnumber, $txt);
    }
    case ($st_vs_legend) {
      if (!$txt) {return -1;}
    }
    else {
      #print "$lstate - ", $txt,"\n";
    }
  }
  return $lstate;                         # Holding state.
}
#
#
sub smartctl_check {
  my ($hash) = @_;
  my @firstline=split(/ /, <>);
  if ($firstline[0] ne "smartctl") {
    print "ERROR! The input stream does not look like smartcl (-x/-a) output - exitting (255)\n";
    exit 255;
  }
  $hash->{"Smartctl"}->{"Version"} = $firstline[1];
}
#
# Initialize state:
my $state=-1;
# Initialize keyvaluehash:
$keyvaluehash->{$k_info}={};
$keyvaluehash->{$k_smart}={};
$keyvaluehash->{$k_smart}->{$k_vendor}={};
$keyvaluehash->{$k_smart}->{$k_general}={};
#
# Read the first line for getting version info:
smartctl_check($keyvaluehash);
#
# Enter the MAIN LOOP for reading rest of the lines:
for(my $line=1;(<STDIN>);$line++) {
  chop;
  my $index = get_index($_,@states);
  if ($index != -1) { $state=$index;}
  else { $state=parseline($state, $line, $_, $keyvaluehash); }
}
#
#
if (cmd_loop($modify_script)) {
  print "Error! Modify script failed - exitting (3)\n";
  exit 3;
}
#
# Dump YAML:
print Dump $keyvaluehash;
#
# Dump JSON:
#print encode_json $keyvaluehash;
