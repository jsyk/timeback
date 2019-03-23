#!/usr/bin/perl

use strict;
use warnings;
use Sys::Hostname;
use FindBin qw($Bin);
use Digest::SHA; # qw(sha1 sha1_hex sha1_base64 ...);
# use Digest::MD5;
use File::Path qw(make_path);
use File::Copy;

use constant RECSEP => "\0\n";

my $host = hostname;
my $sroot = "$Bin/..";
my ($second,$minute,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime time;

# my $viewname = sprintf("%s/%d-%02d-%02d_%02d-%02d-%02d", 
#         $host, $curdt->year, $curdt->month, $curdt->day, 
#         $curdt->hour, $curdt->minute, $curdt->second);
my $viewname = sprintf("%s/%d-%02d-%02d_%02d-%02d-%02d", 
        $host, $year+1900, $month+1, $mday, 
        $hour, $minute, $second);
my $fullviewname = $sroot . '/views/' . $viewname;

my $count_newfiles = 0;
my $count_newdtsize = 0;

my $total_num_files = 0;
my $total_num_incache = 0;
my $total_num_inchamber = 0;
my $total_newbytes = 0;

# list of dirs that must be avoided
my @skipdirs = ();

###################################################################################
# sub SplitToParts
# {
#     my $str = shift;
#     my $plen = shift;
#     my $r = '';
    
#     for (my $i = 0; $i < length($str); $i += $plen) {
#         $r = $r . '/' . substr($str, $i, $plen);
#     }
#     return $r;
# }

###################################################################################
sub SplitDigestToDir        # $digest
{
    my $str = shift;
    my $r = substr($str, 0, 2) . '/' . substr($str, 2, 4) . '/' . substr($str, 6);
    return $r;
}

###################################################################################
sub TakeInFile #($dirname, $name, $hashcache)
{
    my $dirname = shift;
    my $name = shift;
    my $hashcache = shift;
    my $fullname = "$dirname/$name";

    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
        $atime,$mtime,$ctime,$blksize,$blocks) = stat($fullname);

    # can the file be opened at all?
    my $fh;
    if (not open($fh, '<', $fullname)) {
        # no; just skip it...
        print "Error opening '$fullname', skipped.\n";
        return (0, 0);
    }
    close($fh);
    
    my $digest;
    my $fromcache = 0;
    # try to find digest in the cache
    if (exists $hashcache->{$fullname}) {
        # ok it exists in the cache
        my ($c_mtime, $c_size, $c_digest) = @{ $hashcache->{$fullname} };
        if ($c_mtime == $mtime and $c_size == $size) {
            # and the cached time and size equals the actual time and size;
            # therefore we accept the body in the db direct
            $digest = $c_digest;
            $fromcache = 1;
        }
    }
    
    if (not defined($digest)) {
        # compute the digest of the file the hard way
        my $sha = Digest::SHA->new('256');
        print "SHA256 for $fullname\n";
        $sha->addfile($fullname);
        $digest = $sha->hexdigest;
    }
#     my $md5 = Digest::MD5->new;
#     open my $fnamefh, $fullname or die $!;
#     $md5->addfile($fnamefh);
#     close $fnamefh;
#     my $digest = $md5->hexdigest;
    
    #my $prntstr = "    '$name': $fromcache, $digest";
    #print "$prntstr\033[K\033[" . length($prntstr) . "D";
    
    my $hdir = SplitDigestToDir($digest);
    #print "      $hdir\n";
    
    my $fullhdir = "$sroot/db/by-hash/$hdir";
    my $foundchamber = 0;
    if (-d $fullhdir) {
        # already exists in the chamber
        $foundchamber = 1;
    } else {
        # a new file
        make_path($fullhdir);
        copy($fullname, $fullhdir . '/body');
        $total_newbytes = $total_newbytes + $size;
    }
    
    # link in to the view
    my $dirname_decorated = $dirname;
    $dirname_decorated =~ s/:/_/g;          # replace ':' by underscocre

    make_path($fullviewname . '/' . $dirname_decorated);
    link($fullhdir . '/body', $fullviewname . '/' . $dirname_decorated . '/' . $name);

    # note in the hash object the new view name    
    open my $nmlist, '>>' . $fullhdir . '/names' or die $!;
    print $nmlist $viewname . $fullname . RECSEP;
    close $nmlist;
    
    if ($fromcache == 0)
    {
        # object was not in cache, or it is stale -> update the cache
        $hashcache->{$fullname} = [$mtime, $size, $digest];
    }
    
    return ($fromcache, $foundchamber);
}

###################################################################################
sub ScanDir #($dirname)
{
    my $dirname = shift;

    # check that directory is not blacklisted
    foreach my $skipdir (@skipdirs) {
        if ($skipdir eq substr($dirname, 0, length($skipdir))) {
            print "Directory $dirname is blacklisted, skipping. (using $skipdir)\n";
            return;
        }
    }

    # determine the hash-cache file name for the current scanned directory
    my $hcfn_digest = Digest::SHA::sha256_hex($dirname);
    my $hcfn_digest_dir = SplitDigestToDir($hcfn_digest);
    my $hcfname = "$sroot/db/by-name/$host/$hcfn_digest_dir";
    #print "  ScanDir: hcfn_digest=$hcfn_digest, hcfn_digest_dir=$hcfn_digest_dir, hcfname=$hcfname";
    my ($hashcache, $hc_existed) = LoadHashCache("$hcfname/hashcache");

    #print "$dirname";
    opendir my $dirfh, $dirname or die "$!: $dirname\n";
    my @names = readdir($dirfh) or die $!;
    close $dirfh;
    
    my $num_files = 0;
    my $num_dirs = 0;
    my $num_incache = 0;
    my $num_inchamber = 0;
    my $cache_changed = 0;
    
    foreach my $name (@names) {
        next if ($name eq ".");   # skip the current directory entry
        next if ($name eq "..");  # skip the parent  directory entry
        my $fullname = "$dirname/$name";
        
        if (-d $fullname) {            # is this a directory?
            $num_dirs++;
            #print "found a directory: $name\n";
            ScanDir($fullname);
            next;                  # can skip to the next name in the for loop 
        }
        
        my @s = TakeInFile($dirname, $name, $hashcache);
        $num_files++;
        $num_incache += $s[0];
        $num_inchamber += $s[1];

        if ($s[0] == 0)
        {
            # cache had to be modified
            $cache_changed = 1;
        }
    }

    if ($num_files + $num_dirs == 0)
    {
        # the current dir is empty directory; so that it appears in the view we must handle explicit
        my $dirname_decorated = $dirname;
        $dirname_decorated =~ s/:/_/g;          # replace ':' by underscocre
        make_path($fullviewname . '/' . $dirname_decorated);
    }
    
    print "$dirname   ||  HC found: $hc_existed, Files: $num_files / $num_incache / $num_inchamber\n";

    if ($cache_changed == 1)
    {
        # anything in the cache changed -> must save it
        make_path($hcfname);
        SaveHashCache($hashcache, "$hcfname/hashcache");        
    }

    $total_num_files += $num_files;
    $total_num_incache += $num_incache;
    $total_num_inchamber += $num_inchamber;
}

###################################################################################
sub SaveHashCache #(hcache ref, hcfname)
{
    my $hcache = shift;
    my $hcfname = shift;
    
    open my $hcfh, '>' . $hcfname or die $!;
    for my $fullname (keys %$hcache) {
        my @vals = @{ $hcache->{$fullname} };
        print $hcfh $fullname . RECSEP . join(' ', @vals) . RECSEP;
    }
    close $hcfh;
}

###################################################################################
sub LoadHashCache #(hcfname)
{
    my $hcfname = shift;
    my $hcache = {};
    my $hc_exists = 0;
    
    if (-e $hcfname) {
        open my $hcfh, $hcfname or die $!;
        $/ = RECSEP;
        while (<$hcfh>) {
            chomp;
            my $fullname = $_;
            $_ = <$hcfh>;
            chomp;
            my @vals = split(/ /, $_);
            $hcache->{$fullname} = \@vals;
        }
        $/ = "\n";
        close $hcfh;
        $hc_exists = 1;
    }
    return ($hcache, $hc_exists);
}

###################################################################################

print "Welcome to the timeback-machine!\n";
print "Hostname: $host\n";
print "Configuration files are loaded from: $sroot/config/$host\n";

umask(0);       # make everything we create read-writable by all

my $cfgdir = "$sroot/config/$host";
opendir my $dirfh, $cfgdir or die "$!: $cfgdir\n";
my @cfgnames = readdir($dirfh) or die $!;
close $dirfh;

print "Config files found: " . join('|', @cfgnames) . "\n";

# list of dirs from config that shall be scanned
my @scandirs = ();

foreach my $cfgfn (@cfgnames) {
    if ($cfgfn eq '.' or $cfgfn eq '..') {
        next; 
    }
    open my $cfgfh, "$cfgdir/$cfgfn" or die "Opening $cfgdir/$cfgfn:" . $!;
    while (<$cfgfh>) {
        chomp;
        my $dirname = $_;
        if (substr($dirname, 0, 1) eq '-') {
            $dirname = substr($dirname, 1, length($dirname)-1);
            push @skipdirs, $dirname;
            print "NO-SCAN: $dirname\n";
        } else {
            push @scandirs, $dirname;
            print "SCAN: $dirname\n";
        }
    }
    close $cfgfh;
}

print "\nStarting directory walk...\n";

make_path("$sroot/db/by-name");
make_path("$sroot/db/by-hash");

print "# <directory name>   || Files: <num_files> / <num_in_cache> / <num_in_chamber>\n";

foreach my $dirname (@scandirs) {
    ScanDir($dirname);
}

# convert to gigabytes
$total_newbytes = int($total_newbytes / 1024 / 1024) / 1000.0;

print "\n";
print "Procesed files: total $total_num_files / found in cache: $total_num_incache / found in chamber: $total_num_inchamber\n";
print "                added $total_newbytes GB\n";
