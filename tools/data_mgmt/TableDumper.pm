package TableDumper;
use DBI;
use Net::SSH::Perl;
use ProcessLog;
eval "use Math::BigInt::GMP";

sub new {
  my $class = shift;
  my ($dbh, $plog, $user, $host, $pw) = @_;
  my $self = {};
  $self->{dbh} = $dbh;
  $self->{plog} = $plog;
  $self->{user} = $user;
  $self->{host} = $host;
  $self->{pass} = $pw;
  $self->{mysqldump} = "/usr/bin/mysqldump";
  $self->{gzip} = "/usr/bin/gzip";
  $self->{mysqlsocket} = "/tmp/mysql.sock";

  bless $self, $class;
  return $self;
}

sub mysqldump_path {
  my ($self, $path) = @_;
  my $old = $self->{mysqldump};
  $self->{mysqldump} = $path if( defined $path );
  $old;
}

sub gzip_path {
  my ($self, $path) = @_;
  my $old = $self->{gzip};
  $self->{gzip} = $path if( defined $path );
  $old;
}

sub mysqlsocket_path {
  my ($self, $path) = @_;
  my $old = $self->{mysqlsocket};
  $self->{mysqlsocket} = $path if( defined $path );
  $old;
}

sub host {
  my ($self, $new) = @_;
  my $old = $self->{host};
  $self->{host} = $new if( defined $new );
  $old;
}

sub user {
  my ($self, $new) = @_;
  my $old = $self->{user};
  $self->{user} = $new if( defined $new );
  $old;
}

sub pass {
  my ($self, $new) = @_;
  my $old = $self->{pass};
  $self->{pass} = $new if( defined $new );
  $old;
}

sub dump {
  my ($self, $dest, $schema, $table_s) = @_;
  my $cmd = $self->_make_mysqldump_cmd($dest, $schema, $table_s);
  $self->{plog}->d("Starting $cmd");
  eval {
    local $SIG{INT} = sub { die("Command interrupted by SIGINT"); };
    local $SIG{TERM} = sub { die("Command interrupted by SIGTERM"); };
    my $ret = qx/($cmd) 2>&1/;
    if($? != 0) {
      $self->{plog}->e("mysqldump failed with: ". $? >> 8);
      $self->{plog}->e("messages: $ret");
      die("Error doing mysqldump");
    }
  };
  if($@) {
    chomp($@);
    $self->{plog}->es("Issues with command execution:", $@);
    die("Error doing mysqldump");
  }
  $self->{plog}->d("Completed mysqldump.");
  return 1;
}

sub ssh_options {
  my ($self, $opts) = @_;
  my $old = $self->{ssh_options};
  $self->{ssh_options} = $opts if( defined $opts );
  $old;
}

sub remote_dump {
  my ($self, $user, $host, $id, $pass, $dest, $schema, $table_s) = @_;
  my $cmd = $self->_make_mysqldump_cmd($dest, $schema, $table_s);
  $self->{ssh} = Net::SSH::Perl->new($host, identity_files => $id, debug => ProcessLog::_PdbDEBUG >= ProcessLog::Level2, options => [$self->{ssh_options}]);
  eval {
    $self->{plog}->d("Logging into $user\@$host.");
    $self->{ssh}->login($user, $pass);
  };
  if($@) {
    $self->{plog}->e("Unable to login. $@");
    return undef;
  }
  $self->{plog}->d("Running remote mysqldump: '$cmd'");
  eval {
    local $SIG{INT} = sub { die("Remote command interrupted by SIGINT"); };
    local $SIG{TERM} = sub { die("Remote command interrupted by SIGTERM"); };
    my( $stdout, $stderr, $exit ) = $self->{ssh}->cmd("$cmd");
    if($exit != 0) {
      $self->{plog}->e("Non-zero exit ($exit) from: $cmd");
      $self->{plog}->e("Stderr: $stderr");
      die("Remote mysqldump failed");
    }
  };
  if ($@) {
    chomp($@);
    $self->{plog}->es("Issues with remote command execution:", $@);
    die("Failed to ssh");
  }
  $self->{plog}->d("Completed mysqldump.");
  return 1;
}

sub drop {
  my ($self, $schema, $table_s) = @_;
  $self->{plog}->d("dropping: $table_s");
  eval {
    local $SIG{INT} = sub { die("Query interrupted by SIGINT"); };
    local $SIG{TERM} = sub { die("Query interrupted by SIGTERM"); };
    my $drops = map { "`$schema`.`$_`," } @$table_s;
    chop($drops);
    if($drops eq "") {
      $drops = "`$schema`.`$table_s`";
    }
    $self->{plog}->d("SQL: DROP TABLE $drops");
    $self->{dbh}->do("DROP TABLE $drops")
      or $self->{plog}->e("Failed to drop some tables.") and die("Failed to drop some tables");
  };
  if($@) {
    chomp($@);
    $self->{plog}->es("Failed to drop some tables:", $@);
    die("Failed to drop some tables");
  }
  $self->{plog}->d("Completed drop.");
  return 1;
}

sub dump_and_drop {
  my ($self, $dest, $schema, $table_s) = @_;
  $self->{plog}->d("Dumping and dropping: ". join(" $schema.", $table_s));
  $self->dump($dest, $schema, $table_s);
  $self->drop($schema, $table_s);
  return 1;
}

sub remote_dump_and_drop {
  my ($self, $user, $host, $id, $pass, $dest, $schema, $table_s) = @_;
  $self->remote_dump($user, $host, $id, $pass, $dest, $schema, $table_s);
  $self->drop($schema, $table_s);
  return 1;
}

sub _make_mysqldump_cmd {
  my ($self, $dest, $schema, $table_s) = @_;
  my $cmd = qq|if [[ ! -f "$dest.gz" ]]; then $self->{mysqldump} --host $self->{host} --user $self->{user}|;
  $cmd .=" --socket '$self->{mysqlsocket}'" if($self->{host} eq "localhost");
  $cmd .=" --pass='$self->{pass}'" if ($self->{pass});
  $cmd .=" --single-transaction -Q $schema ";
  $cmd .= join(" ", $table_s) if( defined $table_s );
  $cmd .= qq| > "$dest"|;
  $cmd .= qq| && $self->{gzip} "$dest" ; else echo 'Dump already present.' 1>&2; exit 1 ; fi|;
  $cmd;
}

1;