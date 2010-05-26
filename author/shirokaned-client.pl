use strict;
use warnings;
use Test::More;
use Test::TCP;
use Shirokaned;
use AnyEvent::MPRPC::Client;
use AE;
use AnyEvent::HTTP;

my $master_http_port = empty_port();
my $rpc_port_1  = empty_port($master_http_port + 1);
my $rpc_port_2  = empty_port($rpc_port_1 + 1);
test_tcp(
    client => sub {
        test_tcp(
            client => sub {
                my $client = AnyEvent::MPRPC::Client->new(
                    host => '127.0.0.1',
                    port => $rpc_port_1,
                );
                my $client2 = AnyEvent::MPRPC::Client->new(
                    host => '127.0.0.1',
                    port => $rpc_port_2,
                );

                my $ver = $client->call( 'version' )->recv;
                diag $Shirokaned::VERSION;
                is $ver, $Shirokaned::VERSION, 'version';

                my $kcver = $client->call( 'kcversion' )->recv;
                diag "KyotoCabinet->VERSION: $kcver";
                ok $kcver;

                my $slave_status = sub { $client->call('slave_status')->recv() };
                my $setter = sub { $client->call('set' => [$_[0] => $_[1]])->recv };
                my $getter = sub { $client->call('get' => @_)->recv };
                my $count  = sub { $client->call('count')->recv };

                while ($slave_status->() == 0) {
                    warn "SLEEPING";
                    sleep 1;
                    AnyEvent->now_update();
                    my $cv = AE::cv();
                    $cv->send();
                    $cv->recv;
                }

                is $count->(), 0;
                for my $i (0..200) {
                    $getter->("h2"); # use this!
                    $setter->("h$i" => $i+1);
                }
                is $count->(), 112, 'why 112?';

                is $getter->("h1"), undef;
                is $getter->("h100"), 101;
                is $getter->("h2"), 3, "LRU works";

                is $client2->call('get' => "h200")->recv, 201, "replication works";
                is $client2->call('get' => "h2")->recv, undef, "replication works(but, LRU does not works)";

                my $cv = AE::cv();
                http_get "http://127.0.0.1:$master_http_port/h2", sub {
                    $cv->send($_[0]);
                };
                is $cv->recv, '3', 'http interface';

                done_testing;
            },
            server => sub {
                # slave
                my $app = Shirokaned->new(
                    rpc_port  => $rpc_port_2,
                    slave_port => $rpc_port_1,
                    slave_host => "127.0.0.1",
                    dbpath    => '*#capcount=100',
                );
                $app->run();
                AE::cv->recv();
                die "SLAVE ERROR";
            },
            port => $rpc_port_2,
        );
    },
    server => sub {
        # active master
        my $app = Shirokaned->new(
            rpc_port   => $rpc_port_1,
            http_port  => $master_http_port,
            slave_port => $rpc_port_2,
            slave_host => "127.0.0.1",
            dbpath     => '*#capcount=100',
        );
        $app->run();
        AE::cv->recv();
        die "ACTIVE MASTER ERROR";
    },
    port => $rpc_port_1,
);

