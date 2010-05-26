package Shirokaned;
use Mouse;
with 'MouseX::Getopt';
use Twiggy::Server;
use AE;
use KyotoCabinet;
use AnyEvent::MPRPC;
use 5.10.1;

our $VERSION = '0.01';

has http_port => (
    is => 'ro',
    isa => 'Int',
);

has http_host => (
    is => 'ro',
    isa => 'Str',
    default => '0.0.0.0',
);

has rpc_port => (
    is => 'ro',
    isa => 'Int',
    default => 7000,
);

has dbpath => (
    is => 'ro',
    isa => 'Str',
    default => '*',
);

has content_type => (
    is => 'ro',
    isa => 'Str',
);

has slave => (
    is => 'ro',
    isa => 'Str',
);

has db => (
    is => 'ro',
    isa => 'KyotoCabinet::DB',
    default => sub {
        my $self = shift;
        my $db = KyotoCabinet::DB->new();
        $db->open($self->dbpath) or die "cannot open db: " . $db->error;
        $db;
    },
);

has slave_host => (
    is => 'ro',
    isa => 'Str',
);

has slave_port => (
    is => 'ro',
    isa => 'Int',
);

has slave_reconnect => (
    is => 'ro',
    isa => 'Int',
    default => 1,
);

sub _push_guard {
    my ($self, $guard) = @_;
    $self->{_guard} //= [];
    push @{$self->{_guard}}, $guard;
}

sub run {
    my $self = shift;

    # mk slave connection
    my $slave_client;
    if ($self->slave_port) {
        my $reconnector; $reconnector = sub {
            AnyEvent::MPRPC::Client->new(
                host => $self->slave_host,
                port => $self->slave_port,
                on_connect => sub {
                    $slave_client = $_[0];
                },
                on_error => sub {
                    error("slave error: $_[2]");
                    undef $slave_client;
                    my $timer; $timer = AE::timer($self->slave_reconnect, 0, sub {
                        $reconnector->();
                        undef $timer;
                    });
                },
                handler_options => {
                    on_eof => sub {
                        undef $slave_client;
                        my $timer; $timer = AE::timer($self->slave_reconnect, 0, sub {
                            $reconnector->();
                            undef $timer;
                        });
                    },
                },
            );
        };
        my $timer; $timer = AE::timer(0, 0, sub { undef $timer; $reconnector->() }); # first
    }

    # mk rpc server
    my $db = $self->db;
    my $rpc_server = AnyEvent::MPRPC::Server->new(
        port => $self->rpc_port,
        on_error =>
          sub { my ( $handle, $fatal, $message ) = @_; error($message) },
        handler_options => +{},
    );
    $self->_push_guard($rpc_server);
    $rpc_server->reg_cb(
        version => sub {
            my ( $res_cv, @params ) = @_;
            $res_cv->result($VERSION);
        },
        kcversion => sub {
            my ( $res_cv, @params ) = @_;
            $res_cv->result($KyotoCabinet::VERSION);
        },
        set => sub {
            my ( $res_cv, $params ) = @_;
            $db->set($params->[0] => $params->[1]) or error("set error: " . $db->error);
            if ($slave_client) {
                $slave_client->call('slave_set' => $params);
            }
            $res_cv->result( 1 );
        },
        get => sub {
            my ( $res_cv, $params ) = @_;
            my $res = $db->get($params);
            $res_cv->result( $res );
        },
        count => sub {
            my ( $res_cv, @params ) = @_;
            $res_cv->result( $db->count );
        },
        size => sub {
            my ( $res_cv, @params ) = @_;
            $res_cv->result( $db->size );
        },
        status => sub {
            my ( $res_cv, @params ) = @_;
            $res_cv->result( $db->status );
        },
        slave_set => sub {
            my ( $res_cv, $params ) = @_;
            $db->set($params->[0] => $params->[1]) or error("set error: " . $db->error);
            $res_cv->result( 1 );
        },
        slave_status => sub {
            my ( $res_cv, $params ) = @_;
            $res_cv->result( $slave_client ? 1 : 0 );
        },
    );

    if ($self->http_port) {
        my $server = Twiggy::Server->new(
            host => $self->http_host,
            port => $self->http_port,
        );
        $server->register_service($self->_http_handler);
        $self->_push_guard($server);
    }
}

sub _http_handler {
    my $self = shift;
    my $db = $self->db;
    my $content_type = $self->content_type;
    sub {
        my $env = shift;
        my $path = $env->{PATH_INFO};
        $path =~ s!^/!!;
        my $content = $db->get($path);
        my $headers = ['Content-Length' => length($content)];
        if ($content_type) {
            push @$headers, 'Content-Type' => $content_type;
        }
        [200, $headers, [$content]];
    };
}

sub error {
    print STDERR "@_";
}

__PACKAGE__->meta->make_immutable;
