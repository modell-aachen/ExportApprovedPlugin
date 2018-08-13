# See bottom of file for default license and copyright information

package Foswiki::Plugins::ExportApprovedPlugin;

use strict;
use warnings;

use Foswiki::Func    ();
use Foswiki::Plugins ();
use Foswiki::Sandbox ();

use Foswiki::Plugins::KVPPlugin ();

use Encode ();
use File::Path;
use File::Spec;

use version;
our $VERSION = '1.0';
our $RELEASE = '1.0';

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

    # Previous version had TALK suffix and is still there = changeState must have failed somehow
    return if $topic =~ /$Foswiki::cfg{Extensions}{KVPPlugin}{suffix}$/ && Foswiki::Func::topicExists($web, $topic);

    # At this point, if we came from a TALK topic we "know" the transition
    # succeeded because the TALK topic is gone.
    # If we came from a non-TALK topic we need to verify the topic is now
    # approved; that's the only way to tell whether the transition was successful.

    # XXX: may want to check whether the workflow rev increased, too

    my $ntopic = $topic; $ntopic =~ s/$Foswiki::cfg{Extensions}{KVPPlugin}{suffix}$//;

    my ($meta, $text) = Foswiki::Func::readTopic($web, $ntopic);
    if ($ntopic eq $topic) {
        # Check whether draft got approved
        my $ct = Foswiki::Plugins::KVPPlugin::_initTOPIC($web, $topic, 99999,
            $meta, $text); # okay to get this one from cache
        return unless defined $ct;
        return unless $ct->getRow('approved');
    }

    # Make sure export is activated in new version
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
        $template =~ s/%\{\Q$k\E\}/$v/g;
    }
    $template;
}

sub _generateApprovedPdfs {
    my $session = shift;

    my $cfg = $Foswiki::cfg{ExportApprovedPlugin};
    die "$session->{action}: plugin not configured, can't continue" unless ref($cfg) eq 'HASH';
    my $outpath = $cfg->{OutputNameTemplate};

    my $workarea = Foswiki::Func::getWorkArea('ExportApprovedPlugin');
    chdir($Foswiki::cfg{ScriptDir});
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
        $webSh = Foswiki::Sandbox::untaintUnchecked($webSh);
        $topicSh = Foswiki::Sandbox::untaintUnchecked($topicSh);
        $fullfn = Foswiki::Sandbox::untaintUnchecked($fullfn);
        $pdfCmd .= " topic='$webSh.$topicSh' contenttype=application/pdf cover=print \$(cat '$fullfn')";
        my $pdf = `$pdfCmd`;

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
        my ($volume, $dirpart) = File::Spec->splitpath($curpath);
        File::Path::make_path($volume.$dirpart);
        open(my $fh, '>', $curpath) or die "Can't open $curpath for writing: $!";
        print $fh $pdf;

        while (my ($mfn, $mtmpl) = each(%{$cfg->{ExtraFiles}})) {
            Foswiki::Func::pushTopicContext($web, $topic);
            $mtmpl = Foswiki::Func::loadTemplate($mtmpl);
            $mtmpl = Foswiki::Func::expandCommonVariables($mtmpl, $web, $topic, $meta);
            $mfn = _applyParams($mfn, $params);
            ($volume, $dirpart) = File::Spec->splitpath($mfn);
            File::Path::make_path($volume.$dirpart);
            open(my $mfh, '>', $mfn) or die "Can't open $mfn for writing: $!";
            my $from_charset = $Foswiki::cfg{Site}{CharSet} || 'iso-8859-1';
            my $to_charset = $Foswiki::cfg{ExportApprovedPlugin}{ExtraFilesCharSet} || 'windows-1252';
            Encode::from_to($mtmpl, $from_charset, $to_charset) unless $from_charset eq $to_charset;
            print $mfh $mtmpl;
            Foswiki::Func::popTopicContext();
        }

        unlink($fullfn);
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
