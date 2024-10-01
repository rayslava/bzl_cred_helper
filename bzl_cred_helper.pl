#!/usr/bin/perl
use strict;
use warnings;
use JSON;

=head1 NAME

bzl_cred_helper.pl - Extract credentials from a .netrc.gpg file for a given URI

=head1 SYNOPSIS

  $ echo '{"uri":"http://example.com"}' | perl bzl_cred_helper.pl get

=head1 DESCRIPTION

This script reads a JSON input from stdin, extracts the URI, finds the matching
credentials from the decrypted .netrc.gpg file, and outputs JSON-formatted headers
with Authorization token for Bazel.

The script assumes that the credentials are stored in the ~/.netrc.gpg and that
gpg is configured correctly on your host machine (like gpg-agent and so on).

=head1 USAGE

  bazel build --credential_helper=/path/to/bzl_cred_helper.pl '//pkg:*'

=head1 LICENSE

BSD 2-Clause License, see the LICENSE file

=head1 AUTHOR

Slava Barinov <rayslava@gmail.com>

=cut

# pod2text bzl_cred_helper.pl > README

# Check for the correct argument
my $command = shift @ARGV;
die "Expected 'get' as the command argument\n" unless $command eq 'get';

# Read JSON input from stdin
my $input_json = do { local $/; <STDIN> };

# Decode the JSON input
my $input;
eval {
    $input = decode_json($input_json);
};
if ($@) {
    die "Error parsing JSON input: $@\n";
}

# Extract the URI from the JSON input
my $uri = $input->{'uri'};

# Extract the host from the URI, removing the scheme
$uri =~ m#https?://([^/]+)#;
my $host = $1;

# Decrypt .netrc.gpg and read credentials
my $netrc_content = `gpg --quiet --decrypt ~/.netrc.gpg`;
die "Failed to decrypt .netrc.gpg\n" if $? != 0;

# Initialize variables for storing credentials
my ($username, $password, $token);
my $found_host = 0;

# Parse the .netrc content to find credentials matching the host
foreach my $line (split /\n/, $netrc_content) {
    # Check for a matching host line
    if ($line =~ /^machine\s+$host\b/) {
        $found_host = 1;
        # Check if it's a one-line format
        if ($line =~ /login\s+(\S+)\s+password\s+(\S+)/) {
            $username = $1;
            $password = $2;
            $token = $password;  # Use password as the token
            last;
        }
    }
    # Handle multi-line format if host was found
    elsif ($found_host) {
        $username = $1 if $line =~ /login\s+(\S+)/;
        $password = $1 if $line =~ /password\s+(\S+)/;
        $token = $password;  # Use password as the token
        # Stop if both credentials are found
        last if defined $username && defined $password;
    }
}

# Clean up any trailing newline or carriage return characters
chomp($token) if $token;

# Prepare JSON output
my %output;
if ($token) {
    $output{'headers'} = {
        'Authorization' => ["Bearer $token"]
    };
} else {
    %output = ();  # Empty JSON if no token found
}

# Print the JSON output
print encode_json(\%output) . "\n";
