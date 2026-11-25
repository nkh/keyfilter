package KeyFilterTest ;

use strict ;
use warnings ;
use FindBin ;
use File::Temp () ;
use File::Path () ;
use File::Basename () ;
use IO::Select () ;
use POSIX () ;
use Time::HiRes () ;
use Exporter 'import' ;

our @EXPORT =
	(
	'failure_of',
	'rules_from',
	'temp_dir',
	'write_file',
	'read_file',
	'start_pty',
	'read_all',
	'read_until',
	'wait_for_file',
	'process_gone',
	'start_engine',
	'pipe_pair',
	'new_terminal',
	'termios_of',
	'run_engine',
	'engine_process',
	) ;

require "$FindBin::Bin/../keyfilter" ;

alarm 120 ;

my @started ;
our @started_processes ;
my $owner = $$ ;

sub failure_of
{
my ($code) = @_ ;

my $ok = eval { $code->() ; 1 } ;

return $ok ? undef : $@ ;
}

# -----------------------------------------------------------------------------

sub rules_from
{
my (@lines) = @_ ;

my $rules = KeyFilter::Rules->new() ;

$rules->add(scalar KeyFilter::Command::parse_command($_)) for @lines ;

return $rules ;
}

# -----------------------------------------------------------------------------

sub temp_dir { return File::Temp->newdir() ; }

# -----------------------------------------------------------------------------

sub write_file
{
my ($path, @parts) = @_ ;

File::Path::make_path(File::Basename::dirname($path)) ;

open(my $fh, '>', $path) or die "cannot write '$path': $!\n" ;

binmode $fh ;

print $fh @parts ;

close $fh or die "cannot write '$path': $!\n" ;
}

# -----------------------------------------------------------------------------

sub read_file
{
my ($path) = @_ ;

open(my $fh, '<', $path) or die "cannot read '$path': $!\n" ;

binmode $fh ;

local $/ ;

my $text = <$fh> // '' ;

close $fh ;

return $text ;
}

# -----------------------------------------------------------------------------

sub start_pty
{
my (@command) = @_ ;

my $pty = KeyFilter::PTY->new(command => \@command) ;

$pty->spawn() ;

push @started, $pty->pid ;

return $pty ;
}

# -----------------------------------------------------------------------------

sub start_engine
{
my ($arguments, @command) = @_ ;

my %arguments = %$arguments ;

if (!exists $arguments{output})
	{
	open($arguments{output}, '>', '/dev/null') or die "cannot open /dev/null: $!\n" ;
	}

my $pty = KeyFilter::PTY->new(command => \@command, %arguments) ;

$pty->spawn() ;

push @started, $pty->pid ;

return $pty ;
}

# -----------------------------------------------------------------------------

sub pipe_pair
{
pipe(my $read, my $write) or die "pipe: $!\n" ;

$write->autoflush(1) ;

return ($read, $write) ;
}

# -----------------------------------------------------------------------------

sub new_terminal
{
require IO::Pty ;

my $master = IO::Pty->new() ;
my $slave  = $master->slave() ;

return ($master, $slave) ;
}

# -----------------------------------------------------------------------------

sub termios_of
{
my ($fh) = @_ ;

my $termios = POSIX::Termios->new() ;

$termios->getattr(fileno $fh) or die "getattr: $!\n" ;

my %flags =
	(
	iflag => $termios->getiflag(),
	oflag => $termios->getoflag(),
	cflag => $termios->getcflag(),
	lflag => $termios->getlflag(),
	vmin  => $termios->getcc(POSIX::VMIN()),
	vtime => $termios->getcc(POSIX::VTIME()),
	veof  => $termios->getcc(POSIX::VEOF()),
	) ;

return \%flags ;
}

# -----------------------------------------------------------------------------

sub run_engine
{
my ($arguments, @command) = @_ ;

my %arguments = %$arguments ;
my $dir       = File::Temp->newdir() ;
my $data      = delete $arguments{input_data} // '' ;

write_file("$dir/input", $data) ;

open(my $input, '<', "$dir/input") or die "cannot read the input: $!\n" ;
open(my $output, '>', "$dir/output") or die "cannot write the output: $!\n" ;

binmode $input ;
binmode $output ;

my $pty = KeyFilter::PTY->new(command => \@command, input => $input, output => $output, %arguments) ;

my $code  = eval { $pty->run() ; } ;
my $error = $@ ;

push @started, $pty->pid if defined $pty->pid ;

close $output ;

return { code => $code, error => $error, output => read_file("$dir/output"), pty => $pty } ;
}

# -----------------------------------------------------------------------------

# run an engine in a process of its own, driven through pipes

sub engine_process
{
my ($arguments, @command) = @_ ;

my %arguments = %$arguments ;
my $nonblocking = delete $arguments{output_nonblocking} ;

pipe(my $input_read, my $input_write) or die "pipe: $!\n" ;
pipe(my $output_read, my $output_write) or die "pipe: $!\n" ;

my $pid = fork() ;

die "fork: $!\n" unless defined $pid ;

if ($pid == 0)
	{
	close $input_write ;
	close $output_read ;
	
	$output_write->blocking(0) if $nonblocking ;
	
	my %own = %arguments ;
	my $tty = delete $own{tty_input} ;
	
	$own{input} = $tty // $input_read ;
	
	my $pty  = KeyFilter::PTY->new(command => \@command, output => $output_write, %own) ;
	my $code = eval { $pty->run() ; } ;
	
	print STDERR "engine: $@" unless defined $code ;
	
	POSIX::_exit(defined $code ? $code : 255) ;
	}

close $input_read ;
close $output_write ;

$input_write->autoflush(1) ;

my %engine = (pid => $pid, input => $input_write, output => $output_read, done => 0, code => undef) ;

push @started_processes, $pid ;

return bless \%engine, 'KeyFilterTest::Engine' ;
}

# -----------------------------------------------------------------------------

sub read_all
{
my ($fh, $timeout) = @_ ;

return read_until($fh, undef, $timeout) ;
}

# -----------------------------------------------------------------------------

sub read_until
{
my ($source, $pattern, $timeout) = @_ ;

$timeout //= 10 ;

my $pty      = ref($source) eq 'KeyFilter::PTY' ? $source : undef ;
my $fh       = $pty ? $pty->master : $source ;
my $select   = IO::Select->new($fh) ;
my $deadline = Time::HiRes::time() + $timeout ;
my $data     = '' ;

while (Time::HiRes::time() < $deadline)
	{
	return $data if defined $pattern && $data =~ $pattern ;
	
	my $exited = $pty && !$pty->is_running ;
	
	if ($exited || $select->can_read(0.05))
		{
		my $count = sysread($fh, my $chunk, 65536) ;
		
		if (defined $count && $count > 0)
			{
			$data .= $chunk ;
			
			next ;
			}
		
		last if $exited || (defined $count && $count == 0) ;
		
		next if $!{EAGAIN} || $!{EINTR} ;
		
		last ;
		}
	}

return $data ;
}

# -----------------------------------------------------------------------------

sub wait_for_file
{
my ($path, $timeout) = @_ ;

$timeout //= 10 ;

my $deadline = Time::HiRes::time() + $timeout ;

while (Time::HiRes::time() < $deadline)
	{
	return 1 if -s $path ;
	
	Time::HiRes::sleep(0.02) ;
	}

return 0 ;
}

# -----------------------------------------------------------------------------

sub process_gone
{
my ($pid, $timeout) = @_ ;

$timeout //= 5 ;

my $deadline = Time::HiRes::time() + $timeout ;

while (Time::HiRes::time() < $deadline)
	{
	return 1 unless kill 0, $pid ;
	
	my $stat = -r "/proc/$pid/stat" ? read_file("/proc/$pid/stat") : '' ;
	
	return 1 if $stat =~ /\) Z / ;
	
	Time::HiRes::sleep(0.02) ;
	}

return 0 ;
}

# -----------------------------------------------------------------------------

END
	{
	return unless $$ == $owner ;
	
	for my $pid (@started)
		{
		kill 'KILL', -$pid ;
		}
	
	for my $pid (@started_processes)
		{
		kill 'KILL', $pid ;
		}
	}

# -----------------------------------------------------------------------------

package KeyFilterTest::Engine ;

sub pid { return $_[0]->{pid} ; }

# -----------------------------------------------------------------------------

sub send
{
my ($self, $data) = @_ ;

syswrite($self->{input}, $data) // die "send: $!\n" ;

return $self ;
}

# -----------------------------------------------------------------------------

sub close_input
{
my ($self) = @_ ;

close $self->{input} ;

return $self ;
}

# -----------------------------------------------------------------------------

sub read_until
{
my ($self, $pattern, $timeout) = @_ ;

return KeyFilterTest::read_until($self->{output}, $pattern, $timeout) ;
}

# -----------------------------------------------------------------------------

sub read_all
{
my ($self, $timeout) = @_ ;

return KeyFilterTest::read_until($self->{output}, undef, $timeout) ;
}

# -----------------------------------------------------------------------------

sub signal
{
my ($self, $name) = @_ ;

return kill $name, $self->{pid} ;
}

# -----------------------------------------------------------------------------

sub finish
{
my ($self, $timeout) = @_ ;

return $self->{code} if $self->{done} ;

$timeout //= 20 ;

my $deadline = Time::HiRes::time() + $timeout ;

while (Time::HiRes::time() < $deadline)
	{
	my $result = waitpid($self->{pid}, POSIX::WNOHANG()) ;
	
	if ($result == $self->{pid})
		{
		$self->{done} = 1 ;
		$self->{code} = $? & 127 ? 128 + ($? & 127) : $? >> 8 ;
		
		return $self->{code} ;
		}
	
	Time::HiRes::sleep(0.02) ;
	}

kill 'KILL', $self->{pid} ;

waitpid($self->{pid}, 0) ;

$self->{done} = 1 ;
$self->{code} = undef ;

return undef ;
}

package KeyFilterTest ;

1 ;
