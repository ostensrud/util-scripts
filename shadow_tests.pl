#!/usr/bin/perl

# Shadow tests
# Clones a local git repo to another folder and runs unit tests
# Enables you to actually do some work while the tests are running. 
# Useful for when the tests takes some time to complete.

use warnings;
use strict;

use Cwd;
use File::Path qw(remove_tree);
use File::Basename;
use IO::Socket;
use Getopt::Long;

use feature 'say';

my $wd = "build";
my $nice = "nice -19";
my $mvn = $nice . " mvn clean test";
my $icon_path = "/usr/share/icons/oxygen/32x32/actions";
my $xvfb_pid = `pidof /usr/bin/Xvfb`;
my $verbose = 0;
my $tf = "dev/project-test-area";

GetOptions ("verbose" => \$verbose);

verbose("Attempting to find user");

my $user = getpwuid($<);
die "Could not find user." unless $user;

verbose("...Found user $user");

# brukes for å avgjøre om scriptet allerede kjører
my $port = '17038';
my $host = 'localhost';
my $proto = 'tcp';

verbose("Check if an instance is already running...");

my $pid = is_already_running();

if ($pid) {
  verbose("...Found process with pid:$pid. Killing it.");
  kill(-9, $pid);
}
verbose("...Done!");

verbose("Connecting to socket");
start_server();
verbose("...Done");

eval {
  verbose("Setting environment variables");
  set_envir();
  verbose("...Done");

  verbose("Moving to /home/$user/$tf");
  chdir("/home/$user/$tf") or die $!;
  verbose("...Deleting old build folder");
  remove_tree('build');
  verbose("...Done");

  system("git clone /home/oivinds/dev/project $wd"); #TODO: read from current directory

  chdir("/home/oivinds/$tf/$wd");
  print "Current branch: ";
  system("git rev-parse --abbrev-ref HEAD");
  verbose("Start Xvfb if it's not already running");
  system("Xvfb :1&") unless $xvfb_pid;
  verbose("...Done ($xvfb_pid)");

  verbose("Running $mvn");
  system($mvn);

  verbose("Killing child process with pid: $pid");
  kill(-9, $pid);
};

# Reset display to make notify-send show up on the right display
$ENV{DISPLAY} = ":0";

# Kill the process for Xvfb
system("kill -9 $xvfb_pid") if $xvfb_pid;

if ($@) {
  system("notify-send -u low -i $icon_path/application-exit.png 'Build failed'");
  exit(1);
} else {
  system("notify-send -u low -i $icon_path/dialog-ok-apply.png 'Build success'");
}

exit(0);

# Use this to set neccessary envir's
sub set_envir 
{
  # example of oracle-envir's
  $ENV{DATASOURCE_URL}='jdbc:oracle:thin:@localhost:1521:xe';
  $ENV{DATASOURCE_PASSWORD}=$wd;
  $ENV{DATASOURCE_USERNAME}=$wd;

  # which display to use
  $ENV{DISPLAY} = ":1";
}

sub start_server
{
  undef($@);
  my $p_pid = $$;
  my $pid = fork;
  return if $pid;

  my $socket = IO::Socket::INET->new(Listen => 1,
                                  LocalAddr => $host,
                                  LocalPort => $port,
                                  ReuseAddr => 1,
                                  ReusePort => 1,
                                  Proto     => $proto) or die "Could not create socket: $@";

  my $cs = $socket->accept();
  my $cadr = $cs->peerhost();
  my $cprt = $cs->peerport();

  $cs->send($p_pid);
  shutdown($cs, 1);

  $socket->close();
  exit;
}

sub is_already_running
{
  my $socket = new IO::Socket::INET->new(PeerHost => $host,
                                        PeerPort  => $port,
                                        Proto     => $proto);
  if ($@) {
    return 0;
  }

  $socket->recv(my $resp, 1024);
  $socket->close();
  return $resp;
}

sub verbose
{
  say shift if $verbose;
}

