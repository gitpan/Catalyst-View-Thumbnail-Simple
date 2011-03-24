use 5.010001;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Catalyst::View::Thumbnail::Simple',
    VERSION_FROM      => 'lib/Catalyst/View/Thumbnail/Simple.pm', # finds $VERSION
    PREREQ_PM         => { 'Catalyst::View' => 0,
                            'Imager'        => 0,
                            'Image::Info'   => 0, },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Catalyst/View/Thumbnail/Simple.pm', # retrieve abstract from module
       AUTHOR         => 'aesop <aesop@cpan.org>') : ()),
);
