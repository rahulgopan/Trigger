#!/usr/bin/perl
#
# Script is derived from get-times.pl script; except that it
# also finds throughput type scores from a vmware.log.
#
use Time::Local;
use Getopt::Std;
use vars qw/ %opt /; # for Getopt
use strict;

#
# Global Variables Used by Functions too
#
my $showall     = 0; # ignore low/high in results
my $boothalt    = 0; # boothalt of test
my $useHostTime = 1; # common in runlists
my $testname    = "NoName";
my %valhash;    # This hash is used for low, high & final scores.
my %avghash;    # This hash is needed for med & avg scores.
 
# For use with localtime()
my %monthHash = qw(Jan 00 Feb 01 Mar 02 Apr 03 May 04 Jun 05
                   Jul 06 Aug 07 Sep 08 Oct 09 Nov 10 Dec 11);
#
# Functions 
#
sub LogDebug { print shift; }
sub LogError { print shift; }

sub dousage {
   print <<EndUsage;

usage: $0 -i <vmware.log> [ -n <testname> ] [ -u <host|guest> ]

   -i: Full path to the vmware.log to be processed             (required)
   -n: Name of boothalt for VM, not including subtest name     (recommended)
   -u: Use 'host' or 'guest' time, like Testware useHostTime   (recommended)
   -a: Show ALL scores for test, not just low/high/average     (optional)
   -b: Calculate test boothalt time using the vmware.log       (optional)
   -t: User defined boothalt time (in seconds)                 (optional)
   -v: Get vmware tools version number                         (optional)

   Example: 

      $0 -i vmware.log -n jbb.win2k -u guest

EndUsage

   exit 1;
}

# stampToEpoch: Takes a datestamp from the vmware.log and
# converts it to a epoch time.
sub stampToEpoch {
   my $timestamp = $_[0];
   my ($seconds, $epoch) = 0;

   if ($timestamp =~ m/\s/) {
      #
      # OLD format had spaces (new format never has spaces).
      #
      $timestamp =~ s/: .*$//; # Take dumb colon off end of time

      my ($month, $day, $time) = split;
      my ($hour, $min, $sec) = split (':', $time);
      # The timelocal () rounds the seconds, so we will track ourselves
      $epoch = timelocal (0,$min,$hour,$day,$monthHash{$month},0);
      $seconds = $sec; # Contains seconds + fraction of seconds
   }
   else {
      #
      # NEW format separates date and time with a 'T' (no spaces)
      #
      my ($date, $time) = split ('T', $timestamp);
      my ($year, $month, $day) = split ('-', $date);
      my ($hour, $min, $sec) = split (':', $time);

      # We never care about timezones, etc.  Only care about time deltas:
      $sec =~ s/[^.0-9].*$//; # Remove anything after first non-number or dot

      # The timelocal () rounds the seconds, so we will track ourselves
      $epoch = timelocal (0,$min,$hour,$day,($month - 1),0);
      $seconds = $sec; # Contains seconds + fraction of seconds
   }

   return ($seconds + $epoch);
}

# printNow: Outputs arguments into results.txt format.  Here
# would be a good place to support other ourput formats if needed.
sub printNow {
   my $title = $_[0];
   my $meas  = $_[1];
   my $units = $_[2];

   # FIXME: Print other formats too
   print "$title | $meas $units\n";
}

# putScore: Stores score in appropriate data structure for
# later processing OR prints right away, if -a (all).
sub putScore {
   my $title = $_[0];
   my $meas  = $_[1];
   my $units = $_[2];
   my $type  = $_[3];

   # Some tests have the same title but diff units
   my $hashtitle = ("$units:$title");

   # Some Debugging Code (may be commented out)
   if (($useHostTime) && ("seconds" ne $units) && ($valhash{"seconds:$title"})) {
      # If you get this error, you should use '-u guest' when calling this script
      print "header | WARNING Testname Conflict in $title (try -u guest)\n";
   }

   if ($showall) {
      # DEBUG: Uncomment for better debugging
      # print "$title | $meas $units ($type)\n";
      &printNow ($title, $meas, $units);
   }
   else {
      # Need to process measurements, not print right away
      if (($type eq "low") && !$valhash{"$hashtitle"}) {
         # If no previous measurement for low, take it
         $valhash {"$hashtitle"} = $meas;
      }
      else {
         # Seen this one before; check low/high/med
            
	 if ($type eq "low") {
	    # This measurement is smaller
	    if ($meas < $valhash{"$hashtitle"}) {
	       $valhash {"$hashtitle"} = $meas;
	    }
	 }
	 elsif ($type eq "high") {
	    # This measurement is bigger
	    if ($meas > $valhash{"$hashtitle"}) {
	       $valhash {"$hashtitle"} = $meas;
	    }
	 }
	 elsif ($type eq "med") {
	    # Here we can't update the valhash because they
	    # are final values to print.  Will populate the
	    # avghash, and find medians later when we print
	    # the valhash..
	    push(@{$avghash{$hashtitle}}, $meas);
	 }
	 elsif ($type eq "final") {
	    # If flagged final, then there should only be one. 
	    # Don't even bother to save it -- just print it.
	    &printNow ($title, $meas, $units);
	 }
	 elsif ($type eq "timeout") {
       # Some harnesses flag timeouts later.  FIXME: This
       # code invalidates entire test if a timeout occured;
       # Even non-timeout iterations are zeroed, unless a
       # good run happens *after* the timeout
       $valhash {"$hashtitle"} = -1;
       $avghash {"$hashtitle"} = -1;
    }
	 else {
	    # Uhg, I don't handle this type.
	    print "Error: Don't understand $type type for $title\n";
	 }
      }
   } # End: dealing with low/high types
}

sub getBootHalts {
   my $supertest = $_[0];
   my $vmwarelog = $_[1];

   my $startpat = " PowerOn";
   my $endpat   = "VMX exit";

   my $startEpoch = 0;

   open (VMWLOG, "< $vmwarelog") || die ("Could not open $vmwarelog");

   while (<VMWLOG>) {
      chomp;
      my ($stamp, $junk) = split ('\|');

      if (/$startpat/) {
         $startEpoch = &stampToEpoch ($stamp);
      }

      if (/$endpat/) {
         my $endEpoch = &stampToEpoch ($stamp);
         &putScore ($supertest, ($endEpoch - $startEpoch), "seconds", "med");
      }

   }
   close (VMWLOG);
}

sub getResults {
   my $supertest = $_[0];
   my $vmwarelog = $_[1];

   my %lastresult; # Needed for BEGIN/END pairs in $vmwarelog

   # For storing two-part vmware tools version
   my $toolbox = "00000";
   my $toolver = "0000";

   open (VMWLOG, "< $vmwarelog") || die ("Could not open $vmwarelog");

   while (<VMWLOG>) {
      chomp;
      # Old vmware.log formats:
      # Oct 18 17:15:10.628: vcpu-0| Guest: VMQARESULT BEGIN: 4G low
      # Oct 18 17:15:20.328: vcpu-0| Guest: VMQARESULT END: 4G low
      # or
      # Feb 08 12:59:25.644: vcpu-0| Guest: VMQARESULT: high SPECjbb2005 13422.38 bops       
      #
      # New vmware.log formats:
      # 2010-03-16T08:48:35.277Z| vcpu-0| Guest: VMQARESULT BEGIN: divByZero med
      # 2010-03-16T08:49:04.822Z| vcpu-0| Guest: VMQARESULT END: divByZero med
      # or
      # 2010-03-16T09:54:01.654Z| vcpu-2| Guest: VMQARESULT: med Median 17340.90905 trans/sec
      # Even newer vmware.log formats:
      # 2010-03-16T08:48:35.277Z| vcpu-0| I103: Guest: VMQARESULT BEGIN: divByZero med
      # 2010-03-16T08:49:04.822Z| vcpu-0| I103: Guest: VMQARESULT END: divByZero med
      # or
      # 2010-03-16T09:54:01.654Z| vcpu-2| I103: Guest: VMQARESULT: med Median 17340.90905 trans/sec
      if (/VMQARESULT/) {
         my @logMsgArray = split ('\|'); # Maybe 1 or 2 pipe separators; that is okay.
         my $timestamp   = $logMsgArray[0];  # Everything before pipe is some kind of date.
         my $restMsg     = $logMsgArray[-1]; # We never care about middle section, if any.
         my @restMsgArr  = split('VMQARESULT:*', $restMsg);
         my $resultMsg   = $restMsgArr[-1];

         # Actual result log message
         my ($type, $subtest, $varies, $unit) = split(' ', $resultMsg);

         # We will convert timestamp into Epoch and Seconds to calculate delta
         my $epochTime = &stampToEpoch ($timestamp);

         if ($type eq "BEGIN:") {
            # This could be used for sanity checking:
            # $lastresult{"start"}  = $time;
            # $lastresult{"month"}  = $month;
            # $lastresult{"day"}    = $day;
            # $lastresult{"choice"} = $varies;

            # Needed for score:
            $lastresult{"subtest"} = $subtest;
            $lastresult{"epoch"}   = $epochTime;
         }

         elsif ($type eq "END:") {
            # NOTE: This algorithm does NOT work for nested tests.  
            # It assumes every BEGIN is followed by and END before 
            # another BEGIN shows up.  
            if ($subtest ne $lastresult{"subtest"}) {
               print "Error: Found an END before BEGIN for $subtest\n";
               %lastresult = (); # Force the hash empty
               next;
            } 
            my ($length_of_test) = ($epochTime - $lastresult{"epoch"});

            if ($useHostTime) {
               &putScore ("$supertest.$subtest", $length_of_test, "seconds", $varies);
            }
            else {
               # Since we're using HostTime, this measurement is secondary and 
               # we'll give it a different title for "test time" (tt)
               &putScore ("$supertest.${subtest}tt", $length_of_test, "seconds", $varies);
            }
            
         } 

         else {
            # FIXME: I do not deal with useHostTime here!  I think it is
            # probably an error to choose useHostTime *and* have a value
            # here.  If it is not an error, then we must change the test
            # name to not conflict with the BEGIN/END testname.  See how
            # it is done in the case "END:" block above.

            # This is the easy case, a throughput. The $varies column
            # is actually the score
            &putScore ("$supertest.$subtest", $varies, $unit, $type);
         }

      } # End: VMQARESULT parsing

      elsif (/Timeout on Iter/) {
         # This is a special case where we found a timeout in a test (harness killed)
         &putScore ("$supertest", "FAIL", "timeout", "timeout");
         if ($lastresult{"subtest"}) {
            &putScore ("$supertest.$lastresult{\"subtest\"}", "FAIL", "timeout", "timeout");
         }
      }
      elsif (/toolsVersion/) {
         $_ =~ s/"//g;       # Remove occasional "
         $_ =~ s/ \(was.*//; # Remove junk after was..
         # e.g. Jan 20 09:11:03.034: vmx| DISKUTIL: ide0:0 : toolsVersion = 7428
         # e.g. Feb 02 17:07:29.484: vcpu-0| DISKLIB-DDB   : "toolsVersion" = "8192" (was "7428")
         my @toolVerArray = split;
         $toolver = @toolVerArray[$#toolVerArray];
      }
      elsif (/toolbox: Version/) {
         # Jan 22 13:24:55.312: vcpu-0| Guest: toolbox: Version: build-126130
         my @toolBoxArray = split;
         $toolbox = @toolBoxArray[$#toolBoxArray];
         $toolbox =~ s/build-//;
      }
      else {
         next;
      } # End: Reading lines
   }

   close (VMWLOG);

   if ($opt{v}) {
      # If toolbox version is wanted ...
      &putScore ("$supertest.toolsVersion", "$toolver-$toolbox", "", "low");
   }

   #
   # Read through everything!  
   #
   # If user chose show-all, then we printed everything
   # we read in.  If no show-all, then we remembered what
   # we read to do low/high printing (now)....
   if (0 == $showall) {
      # Need to check the avghash for scores...
      my $a;
      foreach $a (keys (%avghash)) {
         # Check if some dummy already put a final
         # (or min/max) score for this test into hash
         if ($valhash {"$a"}) {
            printf ("# Already score for ($a) test: %s\n",
               $valhash {"$a"});
         }
         else {
            # Do the following for Median Scores
            my @ary = sort @{$avghash{$a}};
            my $size   = (1 + $#ary);
            my $middle = ($size / 2);
            $middle =~ s/\..*//; # Strip after decimal
            # Put the median into the valhash as final
            $valhash {"$a"} = $ary[$middle];
            # Done with median
         }
      }
      # Now print our final scores...
      my $k;
      foreach $k (keys (%valhash)) {
         my ($units, $title) = split (':', $k);
         if ($valhash{"$k"} < 0) {
            # Timeouts show up as -1
            # Don't print timeouts in results.txt
            # &printNow ($title, "FAIL", $units);
            printf ("# $title FAIL $units\n");
         }
         else {
            &printNow ($title, $valhash{"$k"}, $units);
         }
      }
   }
}

#
# Main Program
#

getopts ( "abvi:n:t:u:", \%opt );

   # Recommended: Provide a testname
   if ($opt{n}) {
      # Give the name of the test for output
      $testname = $opt{n};
   }

   # Recommended: Set useHostTime like Testware
   if ($opt{u}) {

      if ($opt{u} eq "host")  { 
         $useHostTime = 1; 
      }
      elsif ($opt{u} eq "guest") { 
         $useHostTime = 0; 
      }
      else {
	 print "\nError: Must specify 'host' or 'guest' with -u\n";
	 &dousage ();
      }
   }

   # Optional: Show all scores, not averages
   if ($opt{a}) {
      $showall = 1;
   }

   # Optional: User gave boothalt time for test
   if ($opt{t}) {
      # User specified own boothalt time, maybe via
      # a testharness feature or "time" command.
      $boothalt = $opt{t};
      &putScore ($testname, $boothalt, "seconds", "final");
   }

   # Required: Input file and output type
   if ($opt{i}) {
      # Must provide input & output file

      if (! -f $opt{i} ) {
         print "\nError: Cannot read vmware.log file - $opt{i}\n";
         &dousage ();
      }

      if ($opt{b}) {
         # -b option says calculate boothalt
         &getBootHalts ($testname, $opt{i});
      }
      # This is called for everything
      &getResults ($testname, $opt{i}); 

   }
   else {
      # Nothing else is valid
      &dousage ();
   }

# End GetOpts: Read options

exit 0;
