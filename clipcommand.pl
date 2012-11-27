#!/usr/bin/perl -l

# clipcommand.pl by antirice on perlmonks
# This is released under the same terms as perl

package TempOut;

use overload '""' => 'as_string', fallback => 1;

sub new { 
	my $opt = shift;
	my $content = '';
	open my $t, '>', \$content or die "Unable to open temp stdout: $!";
	my $orig = select $t;
	undef $\ if $opt;
	return bless [ $orig, \$content];
}

sub DESTROY {
	my $self = shift;
	return unless $self->[0];
	select $self->[0];
	undef $self->[0];
	$\ = $/;
}

*release = \&DESTROY;

sub as_string {
	return ${shift->[1]};
}

package TempIn;

sub new {
	my (undef,$txt) = @_;
	open my $fh, "<&STDIN" or die "Unable to duplicate STDIN: $!";
	close STDIN;
	open STDIN, "<", \$txt;
	return bless [ $fh ];
}

sub DESTROY {
	my $self = shift;
	close STDIN;
	open STDIN, "<&", $self->[0] or die "Unable to restore STDIN: $!";
	close $self->[0]
}

package main;

use Win32::Clipboard;
use IPC::Run 'run';
use File::Temp;
use File::Spec::Functions 'rel2abs';
use Text::ParseWords 'shellwords';
use Data::Dumper;
use B::Deparse;
use strict;
use vars '$c';

$/ = "\r\n";
my $v = shift;
$v = $v && $v eq '-v' ? 1 : 0;

$main::c = Win32::Clipboard->new();

my $last = "";
my $count = 0;

my %macros;
my %subs = (
	reload => \&reload,
	list => \&list,
	def_macro => \&def_macro,
	rem_macro => \&rem_macro,
	exit => sub { $c->Set("Good bye ;-)");exit },
	restart => \&restart,
	codefor => \&codefor,
	fullcodefor => \&fullcodefor,
	justrestart => sub { restart([1]) },
	promote_macro => \&promote_macro
);

my %commands;
my %scripts;

# find available commands in commands directory
reload();


while ($c->WaitForChange) {
	next unless $c->IsText && $count++;
	my $t = $c->GetText or next;
	next if  $t eq $last || $t !~ /^'?-+\s*([\w-]+)([ \t]+[^\r\n]+)?[\r\n]*(.*)$/s;
	$last = $t;
	my ($command,$params,$in) = ($1,$2,$3);
	# do this afterwards so we have our variables set before using the regex engine again
	$command = lc $command;
	$params =~ s/^\s+//g; 
	next unless exists $commands{$command};
	if (ref $commands{$command}) {
		print "Executing macro $command";
		eval { $commands{$command}->(parse($params),$in) };
		print "Finished execution";
		print $c->GetText if $v;
		next;
	}
	my $out;
	$c->Set('** EXECUTING **');
	(my $stupid_win = $^X) =~ s/\\/\\\\/g;
	if ($v) {
		print qq{Executing: [$^X "$commands{$command}" $params]};
		print "Parses as: ",Dumper(parse(qq["$stupid_win" "$commands{$command}" $params]));
	}
	eval {
		run(parse(qq["$stupid_win" "$commands{$command}" $params]), \$in, \$out);
	};
	$out = "***** ERROR *****:\n$@" if $@;
	$out =~ s~(?<!\r)\n~$/~g;
	$c->Set($out);
	print $c->GetText if $v;
	$last = $out;
}

sub parse {
   my $line = shift ;
   $line =~ s{(\\[\w\s])}{\\$1}g ;
   return [ shellwords $line ];
   
}

sub reload {
	undef %commands;
	for (<commands/*.pl>) {
		next unless -f;
		my ($check) = m!([\w-]+)\.pl$!g or next;
		$commands{lc $check} = rel2abs($_);
		$commands{lc $check} =~ s/\\/\\\\/g;
	}
	%scripts = %commands;
	%commands = (%commands,%subs,%macros);
	my $out = "Commands available: \r\n";
	$out .= join "\r\n", map qq[ -- $_], sort keys %commands;
	print $out;
	$c->Set(($count ? "Reload successful!\r\n":'').$out);
	print Dumper(\%commands) if $v;
}

sub list {
	my $out = "Commands available: $/";
	$out .= join $/, map qq[ -- $_], sort keys %commands;
	print $out;
	$c->Set($out);	
}

sub def_macro {
	my ($args,$in) = @_;
	my ($name,$opt) = @$args;
	$c->Set("No body for the macro '$name' detected") unless $in;
	my $exec = eval { 'sub { my $temporary_out = TempOut->new("' . ($opt || '') . '"); my $temporary_in;local $_;local *ARGV;local $\\ = $/;local $/ = $/;local ${"} = ${"};local ${,} = ${,};{ my($XYZARGS,$INPUT) = @_;*_ = $XYZARGS;@ARGV = @_;$temporary_in = TempIn->new($INPUT) };' . $in . $/ . '; undef $temporary_in; $main::c->Set($temporary_out->as_string); }' } or warn "Error! $@" and return;
	my $sub = eval { eval $exec or die $@ } or $c->Set("Error creating macro '$name': $@") and print "Body: $/$exec" and return;
	$macros{lc $name} = $commands{lc $name} = $sub;
	local $, = $/;
	print "Built code as: ",B::Deparse->new->coderef2text($sub),"Macro $name successfully created", if $v;
	$c->Set("Macro $name successfully created");
}

sub rem_macro {
	my ($args,$in) = @_;
	my ($name) = @$args;
	$c->Set("Macro $name not found") and return unless exists $commands{$name};
	delete $commands{lc $name};
	delete $macros{lc $name};
	$c->Set("Macro $name successfully removed");
}

sub restart {
	my $args = shift;
	$c->Set("You will lose all macros. Please pass 1 as the first parameter if you wish to continue.") and return unless @$args && $args->[0] eq "1";
	$c->Set("** RESTARTING **");
	print "$/$/Please stay tuned for the following messages.$/$/****** RESTARTING ******$/";
	undef $c;
	exec("$^X $0");
}

sub codefor {
	my $args = lc shift->[0];
	my $out;
	if (exists $macros{$args} && ref $macros{$args}) {
		my @x = map { s/^ {4}//;$_ } split m!\n!,B::Deparse->new->coderef2text($macros{$args});
		$out = join($/, " -- def_macro $args", @x[16..($#x - 3)],"","# End of macro");
	} else {
		$out = "$args is not a macro"
	}
	$c->Set($out);
}

sub fullcodefor {
	my $args = lc shift->[0];
	my $out;
	if (exists $macros{$args}) {
		$out = join $/, split m!\n!,B::Deparse->new->coderef2text($macros{$args});
	} else {
		$out = "$args is not a macro"
	}
	$c->Set($out);
}

sub promote_macro {
	my $args = lc shift->[0];
	my $out;
	if (! exists $macros{$args}) {
		$out = "Macro $args doesn't exist";
	} else {
		$out = eval {
			my @x = map { s/^ {4}//;chomp;$_ } split m!\n!,B::Deparse->new->coderef2text($macros{$args});
			mkdir "commands" unless -d "commands";
			open my $f, '>', rel2abs("commands/$args.pl") or die $@;
			print $f $_ for "#!/usr/bin/perl -l","",'# Macro promoted ' . localtime,'# shift defaults to @_ in subroutines so we ought to copy this over','@_ = @ARGV;','',@x[16..($#x - 3)];
			close $f or die $@;
			delete $macros{$args};
			$commands{$args} = $scripts{$args} = rel2abs("commands/$args.pl");
			"Macro $args successfully promoted!";
		} || "Error promoting macro $args: $@";
	}
	$c->Set($out);
}


__END__
