#!/usr/bin/perl

use strict;
use FixMyStreet::App;
use Text::CSV;
use Getopt::Long::Descriptive;

use constant TITLE => 0;
use constant DESC => 1;
use constant LATLONG => 2;
use constant EMAIL => 3;

my ($opt, $usage) = describe_options(
    '%c %o',
    ['file|f=s',  "path to csv file with list of clinics", { required => 1 } ],
    ['email|e=s', "default email address for the updates to be sent to", { required => 1 } ],
    ['verbose|v',  "print out all services as they are found"],
    ['help',    "print usage message and exit" ],
);
print($usage->text), exit if $opt->help;

my $csv = Text::CSV->new ( { binary => 1 } )  # should set binary attribute.
                or die "Cannot use CSV: ".Text::CSV->error_diag ();
open my $fh, "<:encoding(utf8)", $opt->file or die "Failed to open " . $opt->file . ": $!";

my $clinic_user = FixMyStreet::App->model('DB::User')->find_or_create({
    email => $opt->email
});
if ( not $clinic_user->in_storage ) {
    $clinic_user->insert;
}

# throw away header line
my $title_row = $csv->getline( $fh );

while ( my $row = $csv->getline( $fh ) ) {
    my $clinics = FixMyStreet::App->model('DB::Problem')->search({
        title => $row->[TITLE]
    });

    my ($lat, $long) = split(',', $row->[LATLONG]);
    my $p;
    my $count = $clinics->count;
    if ( $count == 0 ) {
        $p = FixMyStreet::App->model('DB::Problem')->create({
            title => $row->[TITLE],
            latitude => $lat,
            longitude => $long,
            used_map => 1,
            anonymous => 1,
            state => 'unconfirmed',
            name => '',
            user => $clinic_user,
            detail => '',
            areas => '',
            postcode => ''
        });
    } elsif ( $count == 1 ) {
        $p = $clinics->first;
    } else {
        printf "Too many matches for: %s\n", $row->[TITLE];
        next;
    }
    $p->detail( $row->[DESC] );
    $p->latitude( $lat );
    $p->longitude( $long );
    $p->confirm;

    if ( $p->in_storage ) {
        printf( "Updating entry for %s\n", $row->[TITLE] ) if $opt->verbose;
        $p->update;
    } else {
        printf( "Creating entry for %s\n", $row->[TITLE] ) if $opt->verbose;
        $p->insert;
    }
    $p->discard_changes;

    if ( $row->[EMAIL] ) {
        my $u = FixMyStreet::App->model('DB::User')->find_or_create({
            email => $row->[EMAIL]
        });
        $u->insert unless $u->in_storage;
        my $a = FixMyStreet::App->model('DB::Alert')->find_or_create({
            alert_type => 'new_updates',
            user => $u,
            parameter => $p->id
        });
        unless ( $a->in_storage ) {
            printf( "Creating update alert for %s on %s\n", $row->[EMAIL], $row->[TITLE] )
                if $opt->verbose;
            $a->insert;
        }
    }
}
