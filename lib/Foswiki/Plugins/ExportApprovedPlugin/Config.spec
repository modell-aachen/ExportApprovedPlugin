# ---+ Extensions
# ---++ ExportApprovedPlugin

# **STRING M**
# Where to put generated PDF files.
# This is a template for generating the actual filename. You can include the following placeholders:
# $web, $topic - self-explanatory
# $foo - the contents of the form field $foo for the given topic (passed through NameFilter)
$Foswiki::cfg{ExportApprovedPlugin}{OutputNameTemplate} = '$Foswiki::cfg{WorkingDir}/work_areas/ExportApprovedPlugin/output/$web/$topic.pdf';

# **PERL**
# Hashref mapping filename templates (see above) to skin templates that should be used to generate the content of each of the files listed here.
# This can be used to add metadata files that are put alongside the PDF files.
$Foswiki::cfg{ExportApprovedPlugin}{ExtraFiles} = {};

# **STRING**
# Any web.topic that matches this regular expression will be skipped.
$Foswiki::cfg{ExportApprovedPlugin}{SkipTopics} = '^(?:Sandbox|Main|System)\./';

# **PERL H**
$Foswiki::cfg{SwitchBoard}{'generate-approved-pdfs'} = {
    package => 'Foswiki::Plugins::ExportApprovedPlugin',
    function => '_generateApprovedPdfs',
    context => { 'generate-approved-pdfs' => 1 },
};
1;
