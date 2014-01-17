#!/usr/bin/perl -w

#=====================================#
# Author: Moreno 'baro' Baricevic     #
# Contact: baro AT democritos DOT it  #
# File: check_logs.pl                 #
# Date: 16 Jan 2014                   #
#-------------------------------------#
# Prev Modified: 16 Jan 2014          #
# Last Modified: 17 Jan 2014          #
#=====================================#

use strict;
use POSIX qw(strftime);

use Getopt::Long ();
Getopt::Long::Configure ("bundling", "no_ignore_case", "no_ignore_case_always", "no_auto_abbrev");

my $myself = ($0 =~ m|([^/]+)$|)[0];

my $DEBUG = $ENV{DEBUG} ? defined : undef;
my $VERBOSE = 0;

# nagios/icinga exit status
my $EXIT_OK       = 0 ;	# all is fine, thanks for asking
my $EXIT_WARNING  = 1 ;	# something's wrong, but it's not that bad
my $EXIT_CRITICAL = 2 ;	# it's pretty bad, FUBAR & FUD
my $EXIT_UNKNOWN  = 3 ;	# wtf? RTFM

my $got = {
	unk	=> 1 ,	# higher priority has it means usage error or misbehaving
	crit	=> 0 ,
	warn	=> 0 ,
	custom	=> 0 ,	# lowest priority
};

my $RULES_FILE = "./rules";
my $SEEKS_FILE = "./seeks";
my $RULES         = {};
my $SEEKS         = {};
my $RULES_BY_FILE = {};

my $opt = {
	use_prefix		=> 0 ,

	seeks_file		=> undef ,
	seeks_write_only	=> 0 ,
	seeks_read_only		=> 0 ,
	use_llr			=> 0 ,

	rules_file		=> undef ,
	default_message		=> 'PEPPEREPE' ,
	single_rule		=> {
					files => undef ,
					level => undef ,
					message => undef ,
					regexp => undef ,
				} ,
};

my $separator = ':';

#-----------------------------------------------#
# RULES FILE FORMAT
#
# files:level:[message]:regexp ...
#
#	/tmp/pippo*.log:critical:message:regexp
#
#
# \<SEPARATOR>files<SEPARATOR>level<SEPARATOR>message<SEPARATOR>regexp
#
#	\|files|level|message|regexp
#
#	\;/tmp/pippo*.log;critical;message;regexp
#
# - separator: by default ':' is used, any other character can be forced in case the line begins with a '\' followed by the character
# - files: shell glob pattern, including standard wildcards *, ?, [...], ... (man perlfunc / glob)
# - level: keywords WARNING, CRITICAL (values as per nagios/icinga) or any numeric value
# - message: optional message printed in case the given rule matches, as long as it does NOT contain the separator
# - regexp: regular expression. Since it's the last argument, can contain any character, separator included.
#
# Real-world examples:
#	/var/log/secure:CRITICAL:security problem:fail
#	/var/log/messages:WARNING:warning issue:pass
#
#-----------------------------------------------#

#-----------------------------------------------#
# SEEKS FILE FORMAT
#
# file:position:[last_line_read ...]
#
#	/tmp/pippo.log:1256:Dec 1 18:01:47 pippo login: LOGIN ON tty1 BY pippo
#
# - file: filename the line is referring to
# - position: numerical value as returned by tell() and used by seek()
# - last_line_read: optional last line read successfully from the file (@position-length(line))
#
#-----------------------------------------------#

my $S = '|';

#=-----------------------------------------------------------------=#
# return line number of the caller and it's name
sub sub_name()   { my $f=(caller(1))[3]; return (caller(0))[2].$S.(defined $f?$f:'main')}
sub sub_caller() { my $f=(caller(2))[3]; return (caller(1))[2].$S.(defined $f?$f:'main')}

#=-----------------------------------------------------------------=#
# verbose print + optional prefix with debug info (cmdline option)
sub VRBprint(@)
{
	return unless $VERBOSE;
	my $function = sub_caller();
	my $prefix = $opt->{use_prefix} ? "${myself}${S}${function}()${S}[VERBOSE] " : "";
	foreach ( @_ )
	{
		print "$prefix$_";
	}
}

#=-----------------------------------------------------------------=#
# debug print + optional prefix with debug info (cmdline option)
sub DBGprint(@)
{
	return unless defined $DEBUG;
	my $function = sub_caller();
	my $prefix = $opt->{use_prefix} ? "${myself}${S}${function}()${S}[DEBUG] " : "";
	foreach ( @_ )
	{
		print STDERR "$prefix$_";
	}
}

#=-----------------------------------------------------------------=#
# print error/warning messages
# (on stderr, with some predefined prefix)
sub ERRprint(@)
{
	foreach ( @_ )
	{
		print STDERR "*** $myself: $_";
	}
}


#=-----------------------------------------------------------------=#
# print some warning about usage error
sub Usage_error($)
{
	my $message = shift;
	ERRprint "usage error: $message\n" if $message;
	exit $EXIT_UNKNOWN;
}

#=-----------------------------------------------------------------=#
# Usage/Help message + optional warning
sub Usage
{
	my $message = shift;

	print STDERR "\n*** $myself: usage error: $message\n" if $message;

	print STDERR <<EOF;

Usage: $myself [-s SEEKS_FILE] [-w|-n] [-l] [-r RULES_FILE] [-m MESSAGE] [-v] [-d] [-p]
       $myself [OPTIONS...] -F FILES -L LEVEL -R REGEXP [-M MESSAGE]
       $myself {-h|--help}

	-s|--seek SEEKS_FILE	path to seeks log file ($SEEKS_FILE)
				(use -s /dev/null to avoid both reading and writing to a file)
	-w|--seeks-write-only	write seek file, but ignore any previous content
	-n|--seeks-read-only|--dry-run
				read seek file, but don't store any info back to the file
	-l|--use-last-line	read/use/store the last line read, together with last position.
				The 'last line read' field will be ignored and then removed.

	-r|--rules RULES_FILE	path to rules file ($RULES_FILE)
	-m|--default-message MESSAGE
				override default message to print when unspecified in rules file
				[by default '$opt->{default_message}']

	-v|--verbose		verbose output
	-d|--debug		debug output
	-p|--use-prefix		add filename, line, subrouting, flag of each debug/verbose message

	-h|--help		this helpful message

DEFINE SINGLE RULE ON CMDLINE (_ignores_ RULES_FILE)
	-F|--files FILES	file glob pattern
	-L|--level LEVEL	exit value (CRITICAL, WARNING, <NUMBER>)
	-M|--message MESSAGE	optional message
	-R|--regexp REGEXP	regular expression

Example:
	$myself -l -v
	$myself -s /tmp/$myself.seek -r /tmp/$myself.rules -v
	$myself -F "/tmp/*.log" -L CRITICAL -R '201401[0-9]+' -M "got match for January 2014" -v
	$myself -m "something bad found"
	$myself -v -d -p -m 'no message was specified for this rule, but we found a match nonetheless...'
	$myself -w -s /tmp/$myself.lastpos-test-run
	$myself -n -s /tmp/$myself.lastpos-test-run

EOF

	exit $EXIT_UNKNOWN;

}

#=-----------------------------------------------------------------=#
# parse cmdline option and do some sanity checks
sub parse_cmdline
{
	require Getopt::Long;

	Getopt::Long::GetOptions
	(
		'h|help|usage'			=> sub { Usage() } ,
		'v|verbose'			=> \$VERBOSE ,
		'd|debug'			=> \$DEBUG ,
		'p|use-prefix'			=> \$opt->{use_prefix} ,

		's|seeks|seeks-file=s'		=> \$opt->{seeks_file} ,
		'w|seeks-write-only'		=> \$opt->{seeks_write_only} ,
		'n|seeks-read-only|dry-run'	=> \$opt->{seeks_read_only} ,
		'l|use-last-line'		=> \$opt->{use_llr} ,

		'r|rules|rules-file=s'		=> \$opt->{rules_file} ,
		'm|default-message=s'		=> \$opt->{default_message} ,

		'F|files=s'			=> \$opt->{single_rule}->{files} ,
		'L|level=s'			=> \$opt->{single_rule}->{level} ,
		'M|message=s'			=> \$opt->{single_rule}->{message} ,
		'R|regexp=s'			=> \$opt->{single_rule}->{regexp} ,
	) or Usage();


	# SANITY CHECKS

	Usage( "non-option arguments [@ARGV]" ) if @ARGV ;

	if ( defined $opt->{seeks_file} )
	{
		if ( ! length $opt->{seeks_file} )
		{
			Usage_error( "--seeks: null filename given" );
		}
		if ( -e $opt->{seeks_file} )
		{
			if ( not -f $opt->{seeks_file} and not -p $opt->{seeks_file} and not -c $opt->{seeks_file} )
			{
				Usage_error( "--seeks: invalide seeks file [$opt->{seeks_file}] (not a file/pipe/char device)" );
			}
		}
		$SEEKS_FILE = $opt->{seeks_file};
	}

	if ( $opt->{seeks_write_only} and $opt->{seeks_read_only} )
	{
		Usage_error( "--seeks-write-only/--seeks-read-only: conflicting options given, use -s /dev/null instead" );
	}

	if ( defined $opt->{rules_file} )
	{
		if ( ! length $opt->{rules_file} )
		{
			Usage_error( "--rules: null filename given" );
		}
		Usage_error( "--rules: rules file [$opt->{rules_file}] does not exist" ) if not -e $opt->{rules_file};
		if ( not -f $opt->{rules_file} and not -p $opt->{rules_file} and not -c $opt->{rules_file} )
		{
			Usage_error( "--rules: invalid rules file [$opt->{rules_file}] (not a file/pipe/char device)" );
		}
		$RULES_FILE = $opt->{rules_file};
	}

	my $got_rule = (	defined $opt->{single_rule}->{files} or
				defined $opt->{single_rule}->{level} or
				defined $opt->{single_rule}->{regexp} or
				defined $opt->{single_rule}->{message}
	);
	if ( $got_rule )
	{
		my $missing = (	not defined $opt->{single_rule}->{files} or
				not defined $opt->{single_rule}->{level} or
				not defined $opt->{single_rule}->{regexp}
		);
		Usage_error( "--files|--level|--regexp|--message: at least one option specified, but any of files/level/regexp is missing" ) if $missing;
		if ( not defined $opt->{single_rule}->{message} )
		{
			$opt->{single_rule}->{message} = "";
		}
		$opt->{single_rule}->{key} = 'cmdline' ;

#		print "RULE: $opt->{single_rule}->{files} , $opt->{single_rule}->{level} , $opt->{single_rule}->{message} , $opt->{single_rule}->{regexp}\n";
		$RULES = { $opt->{single_rule}->{key} => $opt->{single_rule} };
	}

	if ( defined $DEBUG )
	{
		DBGprint "\$RULES_FILE              = $RULES_FILE\n";
		DBGprint "\$SEEKS_FILE              = $SEEKS_FILE\n";
		DBGprint "\$opt->{seeks_write_only} = $opt->{seeks_write_only}\n";
		DBGprint "\$opt->{seeks_read_only}  = $opt->{seeks_read_only}\n";
		DBGprint "\$opt->{use_llr}          = $opt->{use_llr}\n";
		DBGprint "\$VERBOSE                 = $VERBOSE\n";
		DBGprint "\$DEBUG                   = " . ( ( defined $DEBUG ) ? $DEBUG : "undef" ) . "\n";
		DBGprint "\$opt->{use_prefix}       = $opt->{use_prefix}\n";

		foreach my $key (sort keys %{$RULES})
		{
			DBGprint "\$RULES->{$key}->{files}   = $RULES->{$key}->{files}\n";
			DBGprint "\$RULES->{$key}->{level}   = $RULES->{$key}->{level}\n";
			DBGprint "\$RULES->{$key}->{message} = $RULES->{$key}->{message}\n";
			DBGprint "\$RULES->{$key}->{regexp}  = $RULES->{$key}->{regexp}\n";
			DBGprint "\$RULES->{$key}->{key}     = $RULES->{$key}->{key}\n";
		}
	}
}

#=-----------------------------------------------------------------=#
# die with some error message and given exit value
sub mydie($$)
{
	ERRprint "$_[1]\n";
	exit $_[0];
}

#=-----------------------------------------------------------------=#
# prints out statistics about # of per-file per-rule matches
sub stats()
{
	foreach my $key ( sort keys %$RULES )
	{
		my $rule = $RULES->{$key};
		if ( exists $rule->{match} )
		{
			my %matches = %{$rule->{match}};
			foreach my $file ( sort keys %matches )
			{
				print	"rule #$key: " .
					"message [$rule->{message}]: " .
					"file [$file]: " .
					"pattern [$rule->{regexp}]: " .
					"level [$rule->{level}]: " .
					"matches $matches{$file}" .
					"\n";
			}
		}
	}
}

#=-----------------------------------------------------------------=#
# exit with nagios/icinga compliant exit value and a meaningful
# message
sub myexit()
{
	my $retval = $EXIT_OK;
	if ( $got->{unk} )
	{
		ERRprint "couldn't read any file\n";
		$retval = $EXIT_UNKNOWN;
	}
	if ( $got->{crit} )
	{
		ERRprint "at least one rule matched a CRITICAL condition, got $got->{crit} match(es)\n";
		$retval = $EXIT_CRITICAL;
	}
	if ( $got->{warn} )
	{
		ERRprint "at least one rule matched a WARNING condition, got $got->{warn} match(es)\n";
		$retval = $EXIT_WARNING;
	}
	if ( $got->{custom} )
	{
		ERRprint "custom exit status $got->{custom}\n";
		$retval = $got->{custom};
	}
	stats();
	exit $retval;
}

#=-----------------------------------------------------------------=#
# die reporting a syntax error on rules file
sub syntax_error($$)
{
	mydie( $EXIT_UNKNOWN , "syntax error at line $_[0] [$_[1]]\n" );
}

#=-----------------------------------------------------------------=#
# read and verify rules from rules file
sub get_rules ()
{
	my $RULES_FH = undef;
	my $nrules = 0;
	open( $RULES_FH , "<$RULES_FILE" ) or mydie( $EXIT_UNKNOWN , "cannot open $RULES_FILE" );
	while( <$RULES_FH> )
	{
		chomp();
		next if /^#/;
		next if /^$/;
		if ( s/^\\(.)// )
		{
			$separator = $1;
		}
		syntax_error( $. , $_ ) unless /^([^$separator]+)$separator([^$separator]+)$separator([^$separator]*)$separator(.+)$/;
		$RULES->{$.}->{files}   = $1;
		$RULES->{$.}->{level}   = $2;
		$RULES->{$.}->{message} = $3;
		$RULES->{$.}->{regexp}  = $4;
		$RULES->{$.}->{key}     = $.;
		$nrules++;
	}
	close( $RULES_FH );
	DBGprint "got $nrules rule(s)\n";
	ERRprint "no rules found in [$RULES_FILE]\n" unless $nrules;
	return $nrules;
}

#=-----------------------------------------------------------------=#
# build a table hashed by filename, after expanding glob pattern
sub build_table()
{
#	my $function = (caller(0))[3];
	foreach my $key (sort keys %{$RULES})
	{
		if ( defined $DEBUG )
		{
			DBGprint "rule '$key': files   = $RULES->{$key}->{files}\n";
			DBGprint "rule '$key': level   = $RULES->{$key}->{level}\n";
			DBGprint "rule '$key': message = $RULES->{$key}->{message}\n";
			DBGprint "rule '$key': regexp  = $RULES->{$key}->{regexp}\n";
			DBGprint "rule '$key': key     = $RULES->{$key}->{key}\n";
		}

		my @files = ( glob $RULES->{$key}->{files} );

		if ( ! @files )
		{
			VRBprint "rule '$key': glob [$RULES->{$key}->{files}] didn't expand to any existent file, skipping rule\n";
			next ;
		}

		foreach my $file ( @files )
		{
			if ( $file !~ m|^/.+| )
			{
				VRBprint "rule '$key': glob [$RULES->{$key}->{files}] expanded to a non-absolute path [$file], skipping file\n";
				next ;
			}
			if ( ! -e $file )	# glob should already take care of this
			{
				VRBprint "rule '$key': log file [$file] does not exist, skipping file\n";
				next ;
			}
			if ( ! -f $file and ! -p $file and ! -c $file )
			{
				VRBprint "rule '$key': log file [$file] is not a file/pipe/char device, skipping file\n";
				next ;
			}
			if ( ! -r $file )
			{
				VRBprint "rule '$key': log file [$file] is not readable, skipping file\n";
				next ;
			}
			DBGprint "rule '$key': found valid file $file\n";
			push( @{$RULES_BY_FILE->{$file}} , $RULES->{$key} );
		}
	}
}

#=-----------------------------------------------------------------=#
# parse the log files for any rule that matches a given pattern.
# If a "seek" file exists and it contains useful info, try to seek
# first to the last known position, otherwise start from the
# beginning. Upon success, save the new positions to be later written
# to the "seek" file.
sub analyze_file($$)
{
	my $file = shift;
	my $info = shift;
	my $log_fh = undef;

	DBGprint "analyzing file [$file]\n";

	open( $log_fh , "<$file" ) or mydie( $EXIT_UNKNOWN , "cannot open $file" );
	my $last_line_read = undef;

	if ( exists $SEEKS->{$file} )
	{
		my $pos = $SEEKS->{$file}->{pos};
		my $llr = (exists $SEEKS->{$file}->{llr}) ? $SEEKS->{$file}->{llr} : "";
		if ( not confirm_last_seek( $log_fh , $pos , $llr ) )
		{
			DBGprint "no last seek, back to start\n";
			seek( $log_fh , 0 , 0 );
		}
	}
	DBGprint "current position in file [$file]: " . tell( $log_fh ) . "\n";
	my $something_new = 0;
	while ( <$log_fh> )
	{
		$last_line_read = $_;
		$last_line_read =~ s/[[:cntrl:]]/./g;
		$something_new = 1;
		chomp();
		next unless /./;
		foreach my $rule ( @{$info} )
		{
			my $message = ( $rule->{message} ne "" ) ? $rule->{message} : $opt->{default_message} ;
			if ( /$rule->{regexp}/ )
			{
				$RULES->{$rule->{key}}->{match}->{$file}++;
				$got->{custom} = $rule->{level} if $rule->{level} =~ /^[0-9]+$/;
				$got->{crit} += 1 if $rule->{level} =~ /^CRITICAL$/i;
				$got->{warn} += 1 if $rule->{level} =~ /^WARNING$/i;
				DBGprint "$message: $file:$.: found level $rule->{level} match for regexp [$rule->{regexp}]\n";
				DBGprint "$RULES->{$rule->{key}}->{match}->{$file} match(es) for rule $rule->{key} on file $file]\n";
				VRBprint "$message: $_\n";
			}
		}
	}
	if ( $something_new )
	{
		my $curpos = tell( $log_fh );
		$SEEKS->{$file}->{pos} = $curpos;
		$SEEKS->{$file}->{llr} = $last_line_read ? $last_line_read : "";
	}
	DBGprint "new position and last line for file [$file]: $SEEKS->{$file}->{pos}, [$SEEKS->{$file}->{llr}]\n";
	close( $log_fh );
}

#=-----------------------------------------------------------------=#
# confirm whether the last stored position is "trusted" or we better
# try to read the whole file from the beginning.
sub confirm_last_seek($$$)
{
	my ( $fh , $pos , $last_line ) = @_ ;
	my $lll = length( $last_line );
	my $match = '';

	DBGprint "1\n";

	# invalid position
	return 0 if $pos <= 0 ;

	DBGprint "pos > 0\n";

	# try to seek() to last position
	return 0 if ! seek ( $fh , $pos , 0 ) ;

	DBGprint "seek to pos ok\n";

	# last_line_read is empty, cannot further check, let's assume we are done and satisfied
	return 1 if $lll == 0 ;

	DBGprint "last line is ok\n";

	# last line read is larger than the file... something wrong
	return 0 if $lll > $pos;

	DBGprint "last line less than pos\n";

	# seek back one line and see whether we find a match for the last line read
#	return 0 if ! seek ( $fh , $pos-$lll , 0 );
	return 0 if ! seek ( $fh , -$lll , 1 );

	DBGprint "seek to pos - last line length\n";

	return 0 if ! read( $fh, $match , $lll );

	$match =~ s/[[:cntrl:]]/./g;

	DBGprint "reading match [$match] vs [$last_line]\n";

	return 0 if $match ne $last_line;

	DBGprint "we are exactly where we were the last time\n";

	# ok, both seek and last line matched, we already are in the right place
	return 1;
}

#=-----------------------------------------------------------------=#
# read the "seek" file and obtain file name, last position, and
# optional last line read (if -l/--use-last-line is given on cmdline)
sub get_seeks()
{
	return if $opt->{seeks_write_only};
	my $SEEKS_FH = undef;
	if ( ! open( $SEEKS_FH , "<$SEEKS_FILE" ) )
	{
		ERRprint "cannot open file $SEEKS_FILE for reading\n";
		return;
	}
	while( <$SEEKS_FH> )
	{
		chomp;
		next if /^#/;
		next unless /^([^:]+):([0-9]+):(.*)$/;
		$SEEKS->{$1} = { pos => $2 , llr => $3 };
		if ( ! $opt->{use_llr} )
		{
			$SEEKS->{$1}->{llr} = "";
		}
	}
	close( $SEEKS_FH );
}

#=-----------------------------------------------------------------=#
# write disclaimer, file name, last position, and optional last line
# read (if -l/--use-last-line is given on cmdline) to the "seek"
# file.
sub set_seeks()
{
	return if $opt->{seeks_read_only};
	my $SEEKS_FH = undef;
	if ( ! open( $SEEKS_FH , ">$SEEKS_FILE" ) )
	{
		ERRprint "cannot write to $SEEKS_FILE\n";
		return;
	}
	my $NOW = strftime( "%Y/%m/%d-%H:%M:%S" , localtime( time ) );
	print $SEEKS_FH <<EOF;
#===================================================================#
# This file has been automagically generated at $NOW
# by '$0'.
# DO NOT EDIT. This file will be rewritten (and comments or invalid
# lines stripped out) at the next run. If you really really need to,
# you can set the last position to 0 and/or remove the final field
# (this way forcing the file to be read from the beginning and/or
# just ignoring the last line read).
# Record format:
#		logfile:last position:last line read ...
#===================================================================#
EOF
	foreach my $file ( sort keys %{$SEEKS} )
	{
		my $last = ( $opt->{use_llr} ) ? $SEEKS->{$file}->{llr} : "";
		DBGprint "$file:$SEEKS->{$file}->{pos}:$last\n";
		print $SEEKS_FH "$file:$SEEKS->{$file}->{pos}:$last\n";
	}
	close( $SEEKS_FH );
}

#==========================================================#

MAIN:
{
	# check what the user wants
	parse_cmdline();

	# unless a single rule has been provided on the cmdline, parse the rules file
	if ( ! defined $RULES->{cmdline} )
	{
		# read and verify rules
		my $n = get_rules();
		# or die if no rules can be found
		myexit() unless $n;
	}

	# create a usable table (expand glob, array of per-file rules, hashing by file)
	build_table();

	# do we have any valid logfile to work on?
	my @logfiles = sort keys %{$RULES_BY_FILE};
	if ( ! @logfiles )
	{
		ERRprint "no valid logfiles obtained\n";
		myexit();
	}

	# retrive last positions and optional last lines read
	get_seeks();

	# at this point, the user has no impact on the outcome, so UNKNOWN can be safely set to 0.
	$got->{unk} = 0;

	# hatarakimashou!
	foreach my $logfile (@logfiles)
	{
		# let's analize the logfile
		analyze_file( $logfile , $RULES_BY_FILE->{$logfile} );
	}

	# save last positions and optional last lines read
	set_seeks();

	# exit gracefully with the proper exit value and some meaningful messages
	myexit();

} # /MAIN #

#EOF
