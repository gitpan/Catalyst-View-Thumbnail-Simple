package Catalyst::View::Thumbnail::Simple;

use warnings;
use strict;
use Imager;
use Image::Info qw/image_info dim/;
use base 'Catalyst::View';

our $VERSION = 0.0010;

sub process {
    my ($self, $c) = @_;

    my $stash = $c->stash;
    my $res = $c->res;

    # check for image data
    unless (exists $stash->{image}) {
        $c->error(q{Image data missing from stash, please set 'image' key in} .
                   q{ stash to a scalar ref containing raw image data});
        return $c->res->status(404);
    }

    # derive mime type for response
    my $image_info = image_info $stash->{image};
    my $mime_type = $image_info->{file_media_type};

    my ($w, $h) = dim($image_info);
    my $longest = (sort { $a < $b } ($h, $w))[0];
    my $size = $stash->{image_size};
    my $square = $stash->{square};

    # get type that imager can accept like 'png'
    my $imager_type = $mime_type;
    $imager_type =~ s|^image/||;
    
    my $read_type = $imager_type;
    my $write_type = $stash->{image_type} || $read_type;

    # find out if image needs to be processed at all
    my $should_thumbnail = 0;
    
    # size is smaller than longest side
    $should_thumbnail = 1
        if ($size && ($size < $longest));
    
    # need to crop image
    $should_thumbnail = 1
        if ($square && ($w != $h));

    # write type is different than read type
    $should_thumbnail = 1
        if ($write_type ne $imager_type);

    # force param
    $should_thumbnail = 1
        if $stash->{force_read};


    my $image = undef;
    
    if ($should_thumbnail) {
        # generate thumbnail
        $image = $self->generate_thumbnail($c, $read_type);
    } else {
        # just return it as is
        $stash->{image_data} = $stash->{image};
        $res->content_type($mime_type);
        return $res->body(
            ${ $c->stash->{image} }
        );
    }


    if (ref $image) {
        # image got scaled or read in at least

        # stash the imager object
        delete $stash->{image};
        $stash->{image} = $image;
        
        # quality of output
        my $quality = $stash->{jpeg_quality} || 100;

        # write image data to a scalar
        my $thumbnail;
        $image->write(
            data => \$thumbnail,
            type => $write_type,
            jpegquality => $quality
        );
        
        # stash raw image data
        $stash->{image_data} = \$thumbnail;
        
        # return image in response
        $res->content_type('image/' . $write_type);
        $res->body($thumbnail);
    } else {
        # error out
        $c->error("Couldn't render image: $image");
        return 0;
    }

}


sub generate_thumbnail { 
    my ($self, $c, $type) = @_;

    # check type
    return 'Unable to derive image type from image data, your version of ' .
        'Imager can read in the following image types: ' . 
        join(', ', Imager->read_types) unless $type;
    
    my $stash = $c->stash;
    my $config = $c->config->{'View::Thumbnail::Simple'} || {};

    # max image size allowed, defaults to 15 mb
    my $max_size = $stash->{max_image_size} || 
        $config->{max_image_size} || 15_728_640;

    # read image
    my $image = Imager->new;
    $image->read( 
        data => ${$stash->{image}}, 
        type => $type, 
        bytes => $max_size 
    ) or return 'Imager failed to read image: ' . $image->errstr;
    
    my $size = $stash->{image_size};
    my $square = $stash->{square};
    my $height = $image->getheight;
    my $width = $image->getwidth;

    my ($longest, $shortest) = sort { $a < $b } ($height, $width);

    if ($square && ($height != $width)) {
        # crop
        $image = $image->crop(
            width => $shortest,
            height => $shortest
        );

        $height = $width = $longest = $shortest;
    }

    
    if ($size && ($size < $longest)) {
        # image needs to be scaled

        # pass the right parameter to Imager->scale
        my $dimension = $width > $height ? 
            'xpixels' : 'ypixels';

        # scaling algo to use
        my $qtype = $config->{scaling_qtype} || 'mixing';
        my $new_image = $image->scale( 
            $dimension => $size,
            qtype => $qtype 
        );
        
        # return scaled image
        return $new_image;
    }
    
    # return unchanged image
    return $image;

}

1;

__END__

=pod

=head1 NAME

Catalyst::View::Thumbnail::Simple - Simple Catalyst view class for
thumbnailing images

=head1 SYNOPSIS

    # in a view class of your application

    package MyApp::View::Thumbnailer; 
    use base 'Catalyst::View::Thumbnail::Simple;
    1;

    # in your controller

    my $raw_image_data = $image->data;

    # scale
    $c->stash( 
        image => \$raw_image_data, 
        image_size => 150 
    );
    $c->forward('View::Thumbnailer');


    # crop into a square and scale
    $c->stash( 
        image => \$raw_image_data, 
        image_size => 300, 
        square => 1 
    );
    $c->forward('View::Thumbnailer');

    # scale and transcode image to png
    $c->stash(
        image => \$raw_image_data,
        image_size => 150,
        image_type => 'png'
    );

=head1 DESCRIPTION

This module is a View class for Catalyst that will simply and
efficiently create 'thumbnails' or scaled down versions of images
using arguably the most sane perl image manipulation library,
Imager. The behavior of this module is controlled by stash and config
values.

=head2 Required stash attributes

=over

=item image

A scalar reference containing raw image data.

=back

=head2 Optional stash attributes

=over

=item image_size

An integer in pixels of the desired longest side of the image. It will
be scaled accordingly, maintaining it's original aspect ratio.

=item image_type

You can set this attribute to a string (e.g. 'png') to try to force
Imager to write an image of a certain file format (note that this may
fail). Otherwise the image type is automatically derived from the
source image.

=item square

Set this to true to cause the image to be cropped into a square. See
crop() in L<Imager::Transformations>. Note that this takes place
before the image is scaled (if image_size is available).

=item max_image_size

An integer in bytes of the largest size of image you want Imager to
read (defaults to 15 megabytes). Note that this can also be set in
your application's configuration like so:

    # example in YAML
    View::Thumbnail::Simple:
        max_image_size: 10_485_760

=item force_read

This module will avoid reading in image data unless necessary for
scaling, cropping or transcoding (if the stash values are set,
original image dimensions are checked as well as type).  This is done
to avoid unnecessary re-compression and loss of quality. If you want
to force this module to read and write the image data regardless of
these variables, set this stash key to a true value.

=back

=head2 Optional config parameters

=over 

=item max_image_size

See above section about max_image_size

=item scaling_qtype

Pick what Imager scaling algo to use, defaults to 'mixing'. Please see
the documentation on 'scale()' in L<Imager::Transformations>.

=item jpeg_quality

An integer between 0-100 used to determine the quality of the image when writing JPEG files, defaults to 100. Please see the JPEG section of L<Imager::Files>.

=back

=head2 Returned stash attributes

After generating the thumbnail from the image data, the following
stash values will be set:

=over

=item image

The scaled Imager image object.

=item image_data

A scalar reference containing the raw data of the scaled image (this
could be useful for caching purposes).

=back

=head2 Imager read/write formats

Imager requires several libraries (e.g. libpng, libjpeg) for the
ability to read some image file types. If you are unsure if you have
these dependencies installed, type the following in your command shell
to reveal what image types your version of Imager can currently read:

  perl -MImager -e 'print join(q{, }, Imager->read_types) . qq{\n}'

See the L<Imager> perldocs for more information on image formats.

=head1 COPYRIGHT & LICENSE

Copyright (C) 2011 <aesop@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

1;
