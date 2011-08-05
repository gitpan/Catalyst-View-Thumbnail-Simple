package Catalyst::View::Thumbnail::Simple;

use warnings;
use strict;
use base 'Catalyst::View';

use Imager;
use Image::Info qw/image_info/;

our $VERSION = 0.0006;

sub process {
    my ($self, $c) = @_;

    # check for image data
    unless ( exists $c->stash->{image} ) {
        $c->error( q{Image data missing from stash, please set 'image' key in} .
                   q{ stash to a scalar ref containing raw image data} );
        return $c->res->status(404);
    }

    # derive mime type for response
    my $image_info = image_info $c->stash->{image};
    my $mime_type = $image_info->{file_media_type};

    # get type that imager can accept like 'png'
    my $imager_type = $mime_type;
    $imager_type =~ s|^image/||;

    # default to a stashed type value
    $imager_type = $c->stash->{image_type} || $imager_type;
    
    # quality of output
    my $quality = $c->stash->{jpeg_quality} || 100;

    # generate thumbnail, returns imager object or an error string
    my $image = $self->generate_thumbnail($c, $imager_type);

    if ( ref $image ) {
        # stash the imager object
        delete $c->stash->{image};
        $c->stash->{image} = $image;

        # write image data to a scalar
        my $thumbnail;
        $image->write(
            data => \$thumbnail,
            type => $imager_type,
            jpegquality => $quality
        );
        
        # stash raw image data
        $c->stash->{image_data} = \$thumbnail;
        
        # return image in response
        $c->response->content_type($mime_type);
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

Another thumbnailer? Yes, but this one uses Imager and is simpler than
the other thumbnailers out there (note the `Simple' in the package
name). If you need complex thumbnailing like explicit X & Y values and
cropping/zooming, please see L<Catalyst::View::Thumbnail>.

This module is a View class for Catalyst that will simply and
efficiently create thumbnails or `scaled' versions of images using
arguably the most sane image manipulation library, `Imager'. The
behavior of this module is controlled purely by stash values.

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

You can set this attribute to a string (e.g. `png') to try to force
Imager to read or write an image of a certain file format (note that
this may fail). Otherwise the image type is automatically derived from
the source image.

=item max_image_size

An integer in bytes of the largest size of image you want Imager to
read (defaults to 15 megabytes). Note that this can also be set in
your application's configuration like so:

    # example in YAML
    View::Thumbnail::Simple:
        max_image_size: 10_485_760

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

=head2 `Returned' stash attributes

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
