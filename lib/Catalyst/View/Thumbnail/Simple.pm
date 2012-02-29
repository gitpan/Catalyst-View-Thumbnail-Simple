package Catalyst::View::Thumbnail::Simple;

use warnings;
use strict;
use base 'Catalyst::View';

use Imager;
use Image::Info qw/image_info dim/;

our $VERSION = 0.0009;

sub process {
    my ($self, $c) = @_;

    my $stash = $c->stash;

    # check for image data
    unless ( exists $stash->{image} ) {
        $c->error( q{Image data missing from stash, please set 'image' key in} .
                   q{ stash to a scalar ref containing raw image data} );
        return $c->res->status(404);
    }

    # derive mime type for response
    my $image_info = image_info $stash->{image};
    my $mime_type = $image_info->{file_media_type};

    # get size to see if we need to read it in
    my ($w, $h) = dim($image_info);
    my $longest = $w > $h ? $w : $h 
        if $w && $h;

    # get type that imager can accept like 'png'
    my $imager_type = $mime_type;
    $imager_type =~ s|^image/||;
    
    # type to read image in as
    my $read_type = $imager_type;
    
    # type to write image out as, use stashed value if available or read type
    my $write_type = $stash->{image_type} || $read_type;

    # check if we need to force thumbnailing by force param or if the
    # stashed image type is not the same as what we got from the image
    my $force = 0;
    $force = 1 if $stash->{force_read} || 
        ($stash->{image_type} && $stash->{image_type} ne $imager_type);

    
    # quality of output
    my $quality = $stash->{jpeg_quality} || 100;
    my $size = $stash->{image_size};
    
    my $image = undef;
    
    if ( ($size && (!($size >= $longest))) || $force) {
        # if a size is available and it isn't greater than the longest
        # side of the image or there is a force param then generate
        # the thumbnail, returns imager object or an error string
        $image = $self->generate_thumbnail($c, $read_type);
    } else {
        # if it doesnt need to be scaled just return it
        $c->stash->{image_data} = $c->stash->{image};
        $c->response->content_type($mime_type);
        return $c->response->body(${ $c->stash->{image} });
    }

    if (ref $image) {
        # image got scaled or read in at least

        # stash the imager object
        delete $c->stash->{image};
        $c->stash->{image} = $image;

        # write image data to a scalar
        my $thumbnail;
        $image->write(
            data => \$thumbnail,
            type => $write_type,
            jpegquality => $quality
        );
        
        # stash raw image data
        $c->stash->{image_data} = \$thumbnail;
        
        # return image in response
        $c->response->content_type('image/' . $write_type);
        $c->response->body($thumbnail);
    } else {
        # error out
        $c->error("Couldn't render image: $image");
        return 0;
    }

}


sub generate_thumbnail { 
    my ($self, $c, $type) = @_;

    # check type
    return ( 'Unable to derive image type from image data, set the correct ' . 
             '$c->stash->{type} accordingly to one of the following values: ' . 
             join(', ', Imager->read_types) ) unless $type;
    
    # max image size allowed, defaults to 15 mb
    my $max_size = $c->stash->{max_image_size} || 
        $c->config->{'View::Thumbnail::Simple'}->{max_image_size} || 15_728_640;

    # read image
    my $image = Imager->new;
    $image->read( data => ${$c->stash->{image}}, 
                  type => $type, bytes => $max_size )
        or return 'Imager failed to read image: ' . $image->errstr;
    
    my $size = $c->stash->{image_size};

    my $height = $image->getheight;
    my $width = $image->getwidth;

    # get longest side to see if it needs to be scaled down
    my $longest = $height > $width ? $height : $width;
    
    if ( $size && ( $size < $longest ) ) {
        # image needs to be scaled
        
        # amazing algorithm to find the longest side of the image and
        # pass the right parameter to Imager->scale
        my $dimension = $width > $height ? 
            'xpixels' : 'ypixels';

        # scaling algo to use
        my $qtype = $c->config->{'View::Thumbnail::Simple'}->{scaling_qtype} || 'mixing';
        my $new_image = $image->scale( $dimension => $size,
                                       qtype => $qtype );
        
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
    $c->stash( image => \$raw_image_data, image_size => 150 );
    $c->forward('View::Thumbnailer');

=head1 DESCRIPTION

This module is a View class for Catalyst that will simply and
efficiently create 'thumbnails' or scaled down versions of images
using arguably the most sane image manipulation library,
L<Imager>. The behavior of this module is controlled purely by stash
values.  If you need complex thumbnailing like explicit X & Y values
and cropping/zooming, please see L<Catalyst::View::Thumbnail>.

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

=item max_image_size

An integer in bytes of the largest size of image you want Imager to
read (defaults to 15 megabytes). Note that this can also be set in
your application's configuration like so:

    # example in YAML
    View::Thumbnail::Simple:
        max_image_size: 10_485_760

=item force_read

This module will avoid reading & writing image data out unless an
image_size value is available in the stash and it is less than the
size of the longest side of the image data to be scaled. This is done
to avoid unnecessary image compression (loss of quality). If you want
to force this module to read and write the image data regardless of
these variables (e.g. if you wanted to transcode it to another file
format), either set this stash value to a true value or set the
'image_type' stash value to an Imager acceptable file extension
(e.g. 'jpeg') that is different than the type of the current stashed
image data.

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

=head2 'Returned' stash attributes

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
