#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw(abs_path getcwd);

use feature 'say';

die "Usage: $0 path/to/folder/with/repos\n" unless (@ARGV == 1);

# Colors and formatting
my $reset = "\e[0m";
my $red = "\e[31m";
my $green = "\e[32m";
my $bold = "\e[1m";

my $remote_name = "origin"; # could look this up but for now we'll just assume
my $skip_current_branch = 0;
my $path = abs_path(shift);

die "$path is not a folder\n" unless (-d $path);

opendir( my $DIR, $path );

my @subfolders = readdir $DIR;

# Remove everything that's not a directory and directories starting with .|..
@subfolders = grep { -d "$path/$_" && ! /^\.{1,2}/} @subfolders;

foreach (sort(@subfolders)) {
  chdir("$path/$_");
  my $current = getcwd();

  # Check if the folder actually is a git repo...
  next if system("git rev-parse 2> /dev/null");
  # ...and that it has a remote
  next unless `git remote -v`;

  say $green . "Processing $current" . $reset;

  system("git remote update $remote_name --prune");

  my $current_branch = `git rev-parse --abbrev-ref HEAD`;
  chomp($current_branch);

  # Find local branches and their tracking status
  my $lb = `git branch -vv`;
  my @lines = split("\n", $lb);

  my %prunes;
  foreach my $line (@lines) {
    $prunes{$1} = "1" if $line =~ /.+?\[$remote_name\/(.+)?: gone\]/;
  }

  next unless(keys(%prunes)); 

  say $bold . "The following local branches will be deleted:" . $reset; 
  say $_ foreach keys %prunes;
  say "Proceed? [y|n]";
  my $response = <STDIN>;
  next unless ($response =~ /[Yy]/);

  if ($prunes{$current_branch}) {
    say $green."You're on a branch that will be deleted. Moving to master.".$reset;
    # Check if there are local, uncommited changes
    system("git diff-index --quiet HEAD --");
    unless($?) {
      # No local changes, move to master and merge from origin
      `git checkout master && git merge origin/master`;
    } else {
      $skip_current_branch = 1;
      say $red . "Your branch, " . $bold . $current_branch . $reset . $red . ", which is deleted on the remote has local uncommited changes. Skipping this one." . $reset;
    }
  }

  foreach (keys %prunes) {
    next if $current_branch eq $_ && $skip_current_branch;
    `git branch -d $_ 2> /dev/null`;
    if ($?) {
      say $red . "The branch $_ is not fully merged." . $reset;
      print $red . "Would you like to delete it? [y|n]: " . $reset;
      $response = <STDIN>;
      next unless ($response =~ /[Yy]/);
      `git branch -D $_`;
    }
  }
  say "";
}

close $DIR;

