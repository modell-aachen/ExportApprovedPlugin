# See bottom of file for default license and copyright information

package Foswiki::Plugins::ExportApprovedPlugin;

use strict;
use warnings;

use Foswiki::Func    ();
use Foswiki::Plugins ();
use Foswiki::Sandbox ();

use Foswiki::Plugins::KVPPlugin ();

use version;
our $VERSION = '0.0.1';
our $RELEASE = '0.0.1';

our $SHORTDESCRIPTION = 'Exports approved topics as PDF files for use in third-party systems';
our $NO_PREFS_IN_TOPIC = 1;

my $topicOfInterest;

sub initPlugin {
    my ($topic, $web, $user, $installWeb) = @_;

    if ($Foswiki::Plugins::VERSION < 2.0) {
        Foswiki::Func::writeWarning('Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm');
        return 0;
    }

    undef $topicOfInterest;
    my $session = $Foswiki::Plugins::SESSION;
    my $req = $session->{request};
    if ($req->action eq 'rest' && $req->path_info =~ m#/KVPPlugin/changeState#) {
        return 1 if $topic =~ /$Foswiki::cfg{ExportApprovedPlugin}{SkipTopics}/;
        return 1 unless $topic =~ /$Foswiki::cfg{Extensions}{KVPPlugin}{suffix}$/;
        my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
        return 1 unless defined $meta;
        return 1 unless $meta->find('WORKFLOW');
        # It exists and it has workflow info; now all we need to check at this
        # point is whether the workflow action will approve the topic
        my $ct = Foswiki::Plugins::KVPPlugin::_initTOPIC($web, $topic, 99999,
            $meta, $text, Foswiki::Plugins::KVPPlugin::FORCENEW);
        return 1 unless defined $ct;
        return 1 if $ct->getRow('approved'); # unlikely but let's check anyway
        my $nextState = $ct->haveNextState($req->param('WORKFLOWACTION'));
        return 1 unless $nextState;
        $nextState = $ct->{workflow}->getFields($nextState);
        return 1 unless defined $nextState && $nextState->{approved};
        $topicOfInterest = [$web, $topic];
    }

    return 1;
}

sub finishPlugin {
    return unless defined $topicOfInterest;

    my ($web, $topic) = @$topicOfInterest;

    undef $topicOfInterest;

    return if Foswiki::Func::topicExists($web, $topic);

    # The original topic had WORKFLOWSUFFIX; now it's gone. We already checked
    # that the transition was one that approves the topic, so we can (almost)
    # safely conclude that the topic was approved successfully.

    # XXX: may want to check whether the workflow rev increased, too

    # Make sure export is activated in new version
    my ($ntopic) = ($topic =~ /^(.*)$Foswiki::cfg{Extensions}{KVPPlugin}{suffix}$/);
    my ($meta) = Foswiki::Func::readTopic($web, $ntopic);
    return if !$meta->getPreference('EXPORT_AS_PDF');

    my $landscape = $meta->getPreference('PDF_LANDSCAPE') || '0';
    $landscape = '0' unless $landscape =~ /^(1|on|yes|true)$/;

    my $paper = $meta->getPreference('PDF_PAPERSIZE') || 'A4'; $paper = uc($paper);
    $paper = 'A4' unless $paper eq 'A3';

    my $webfn = $web; $webfn =~ s#/#.#g;
    open my $notifile, '>', Foswiki::Func::getWorkArea('ExportApprovedPlugin')
        ."/$webfn.$topic";
    print $notifile "landscape=$landscape printpagesize=$paper";
}

sub _applyParams {
    my ($template, $params) = @_;
    while (my ($k, $v) = each(%$params)) {
        $template =~ s/\$\{\Q$k\E\}/$v/g;
    }
    $template;
}

sub _generateApprovedPdfs {
    my $session = shift;

    my $cfg = $Foswiki::cfg{ExportApprovedPlugin};
    die "$session->{action}: plugin not configured, can't continue" unless ref($cfg) eq 'HASH';
    my $outpath = $cfg->{OutputNameTemplate};

    my $workarea = Foswiki::Func::getWorkArea('ExportApprovedPlugin');
    foreach my $fn (<$workarea/*>) {
        next if !-f $fn;
        my $fullfn = $fn;
        $fn =~ s#^$workarea/##;
        next if $fn =~ /^\./;

        my ($web, $topic) = ($fn =~ /^(.*)\.(.*)$/);

        $topic =~ s/$Foswiki::cfg{Extensions}{KVPPlugin}{suffix}$//;
        my ($meta) = Foswiki::Func::readTopic($web, $topic);

        $web =~ s/\./\//g;
        my $webSh = $web; $webSh =~ s/'/'\\''/g;
        my $topicSh = $topic; $topicSh =~ s/'/'\\''/g;

        my $pdfCmd = "$Foswiki::cfg{ScriptDir}/view$Foswiki::cfg{ScriptSuffix}";
        $fullfn =~ s/'/'\\''/g;
        $pdfCmd .= " topic='$webSh.$topicSh' contenttype=application/pdf cover=print $(cat '$fullfn')";
        my $pdf = `$pdfCmd`;

        my ($meta) = Foswiki::Func::readTopic($web, $topic);
        unless (defined $meta) {
            print STDERR "Couldn't read metadata for $web.$topic, skipping...\n";
            next;
        }
        my $params = {
            web => $web,
            topic => $topic,
        };
        foreach my $field ($meta->find('FIELD')) {
            $params->{$field->{name}} = $field->{value};
        }
        my $curpath = _applyParams($outpath, $params);
        open(my $fh, '>', $curpath) or die "Can't open $curpath for writing: $!";
        print $fh $pdf;

        while (my ($mfn, $mtmpl) = each(%{$cfg->{ExtraFiles}})) {
            Foswiki::Func::pushTopicContext($web, $topic);
            $mtmpl = Foswiki::Func::loadTemplate($mtmpl);
            $mtmpl = Foswiki::Func::expandCommonVariables($mtmpl, $web, $topic, $meta);
            $mfn = _applyParams($mfn, $params);
            open(my $mfh, '>', $mfn) or die "Can't open $mfn for writing: $!";
            print $mfh $mtmpl;
            Foswiki::Func::popTopicContext();
        }
    }
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: %$AUTHOR%

Copyright (C) 2014 Modell Aachen GmbH

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
