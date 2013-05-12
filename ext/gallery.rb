# Christophe Haus 2011 - 2012 based on the work of Thomas Leitner.
#

require 'RMagick'
require 'exifr'

# Objects of this class represent a whole image gallery and are available in all image gallery page files.
class GalleryInfo

   # A helper module that allows acessing and changing data via the bracket notation.
   module KeyAccess

     def []( key )
       @data[key]
     end

     def []=( key, value )
       @data[key] = value
     end

   end

   # A helper module which declares common attributes for gallery pages.
   module ItemHelper

     include KeyAccess

     # The name of the page.
     attr_accessor :pagename

     # The title of the page.
     attr_reader :title

     # Meta data for the page.
     attr_reader :data

     def initialize( pagename, data )
       @pagename = pagename
       @title = data['title']
       @data = data
     end

   end

   # Represents an image page.
   class Image

     include ItemHelper

     # The name of the image file.
     attr_reader :filename

     # The name of the image file.
     attr_reader :src_filename

     def initialize( pagename, data, src_filename, filename )
       super( pagename, data )
       @filename = filename
       @src_filename = src_filename
     end

     # Returns the thumbnail image tag for the image.
     def thumbnail( attr = {} )
       attr = attr.collect {|k,v| "#{k}='#{v}'"}.join( ' ' )
       if !@data['thumbnail'].to_s.empty? && @data['thumbnail'] != @filename
         "<img src=\"#{@data['thumbnail']}\" alt=\"#{@title}\" #{attr}/>"
       else
         width, height = (@data['thumbnailSize'] || '').split('x')
         "<img src=\"#{@filename}\" width=\"#{width}\" height=\"#{height}\" alt=\"#{@title}\" #{attr}/>"
       end
     end

     # Returns the thumbnail image src for the image.
     def thumbnail_src( )
       if !@data['thumbnail'].to_s.empty? && @data['thumbnail'] != @filename
         "#{@data['thumbnail']}"
       end
     end

     # Returns the width for the image.
     def width( )
       if !@data['exif'][:width].to_s.empty?
         "#{@data['exif'][:width]}"
       end
     end

     # Returns the height for the image.
     def height( )
       if !@data['exif'][:height].to_s.empty?
         "#{@data['exif'][:height]}"
       end
     end

     # Returns the date that the image/photo was taken.
     def date_taken( )
       months = ["Januari", "Februari", "Maart", "April", "Mei", "Juni", "Juli", "Augustus", "September", "Oktober", "November", "December"]
       @data['exif'][:date_time_original].to_s.empty? ? "" : "#{months[@data['exif'][:date_time_original].month-1]} #{@data['exif'][:date_time_original].day}, #{@data['exif'][:date_time_original].year}"
     end

   end

   # Represents an image gallery.

   include ItemHelper
   include KeyAccess

   # A index image for this gallery.
   attr_reader :index_image

   # A collage image for this gallery.
   attr_reader :collage_image

   # A list of images for this gallery.
   attr_reader :images

   # The index for the current image in the current gallery or +nil+ if there is no current image.
   attr_reader :iIndex

   # The main page object if it exists; otherwise +nil+.
   attr_accessor :mainpage

   # The whole data hash for the image gallery.
   attr_reader :data

   def initialize( pagename, data, index_image, collage_image, images )
     super( pagename, data )
     @index_image = index_image
     @collage_image = collage_image
     @images = images
   end

   # Returns the thumbnail image tag for the gallery.
   def thumbnail( attr = {} )
     @images.first.thumbnail( attr )
   end

   # Returns the current image.
   def cur_image
     @images[@iIndex]
   end

   # Returns the current image id.
   def get_cur_image_id
     @iIndex
   end

   # Returns the current image id.
   def set_cur_image_id (iIndex)
     @iIndex = iIndex
   end

   # Returns the previous image using the given +gIndex+ and +iIndex+, if it exists, or +nil+ otherwise.
   def prev_image(iIndex = @iIndex )
     if iIndex == 0
       result = nil
     else
       result = @images[iIndex - 1]
     end
     return result
   end

   # Returns the next image using the given +gIndex+ and +iIndex+, if it exists, or +nil+ otherwise.
   def next_image(iIndex = @iIndex )
     if iIndex == @images.length - 1
       result = nil
     else
       result = @images[iIndex + 1]
     end
     return result
   end

   # Returns the modified time (object).
   def modified
     @data['mtime'].nil? ? Time.new : @data['mtime']
   end

   # Returns the modification time.
   def modified_ext
     months = ["Januari", "Februari", "Maart", "April", "Mei", "Juni", "Juli", "Augustus", "September", "Oktober", "November", "December"]
     @data['mtime'].nil? ? "" : "#{months[@data['mtime'].month-1]} #{@data['mtime'].year}"
   end

   # Returns the sort info.
   def sort_info
     @data['sort_info'].nil? ? 0 : @data['sort_info'].to_s.to_i
   end

   def shorten_description (count = 30)
     if ! @data['description'].to_s.empty?
       if @data['description'].length >= count
         shortened = @data['description'][0, count]
         splitted = shortened.split(/\s/)
         words = splitted.length
         splitted[0, words-1].join(" ") + ' &#8230;'
       else 
         @data['description']
       end
     else
	   '&#8230;'
     end
   end

end


class Gallery
   include Webgen
   include SourceHandler::Base
   include WebsiteAccess
   include Magick

   alias :create_page_node :create_node

   def self.setup
     config = Webgen::WebsiteAccess.website.config
     config.patterns('Gallery' => ['**/*.gallery'])
     config['sourcehandler.invoke'][5] << 'Gallery'
   end

   def create_node(path)
     @nodes = []

#     puts path.inspect
#     puts path.path
#     puts path.source_path
#     puts path.parent_path
#     puts path.meta_info.inspect

     @page_path = path             # Path used for creating nodes for the actual content page
     @g_path = path.dup            # Path used for creating nodes for the gallery page
     @img_path = path.dup          # Path used for creating nodes for images
     @tn_path = path.dup           # Path used for creating nodes for thumbnails
     @collage_img_path = path.dup  # Path used for creating nodes for collages
     @index_img_path = path.dup    # Path used for creating nodes for index images

     file = File.join("src", path)
     mtime = File.mtime(file)
     @src_path = File.dirname( file )

     @defaultfiledata = {
       "galleryPageTemplate"  =>  '../gallery_gallery.template',    # The template for gallery pages. If nil or a not existing file is specified, the default template is used.
       "imagePageTemplate"    =>  '../gallery_image.template',      # The template for image pages. If nil or a not existing file is specified, the default template is used.
       "images"               =>  'images/**/*.jpg'                 # The path pattern for specifying the image files.
     }

     @filedata = {}
     @imagedata = {}
     begin
       filedata = []
       YAML::load_documents( File.read( file ) ) { |d| 
         filedata << d 
       }
       @filedata = filedata[0] if filedata[0].kind_of?( Hash )
       @imagedata = filedata[1] if filedata[1].kind_of?( Hash )
     rescue
       log(:error) { "Could not parse gallery file <#{file}>, not creating gallery pages" }
       return
     end

     images = @imagedata.keys
     images.sort! do |a,b|
       aoi = @imagedata[a].nil? ? 0 : @imagedata[a]['sort_info'].to_s.to_i || 0
       boi = @imagedata[b].nil? ? 0 : @imagedata[b]['sort_info'].to_s.to_i || 0
       atitle = @imagedata[a].nil? ? a : @imagedata[a]['title'] || a
       btitle = @imagedata[b].nil? ? b : @imagedata[b]['title'] || b
       (aoi == boi ? atitle <=> btitle : aoi <=> boi)
     end

     @filedata['title'] ||= File.basename( file, '.*' ).capitalize
     @filedata['filename'] ||= @filedata['title'].downcase
     @filedata['lang'] ||= website.config['website.lang']
     @filedata['mtime'] ||= mtime
     log(:info) { "Creating gallery for file <#{file}> with #{images.length} images" }

     # create nodes and setup objects
     create_gallery( images )

     @nodes
   end

   def content(node)
     if node.node_info.has_key?(:page)
       ###########################
       # node is a html page
       ###########################
       block_name = 'content'
       templates = website.blackboard.invoke(:templates_for_node, node)
       chain = [templates, node].flatten
       if chain.first.node_info[:page].blocks.has_key?(block_name)
         node.node_info[:used_nodes] << chain.first.alcn
         context = chain.first.node_info[:page].blocks[block_name].render(Webgen::Context.new(:chain => chain))
         context.content
       else
         raise Webgen::RenderError.new("No block named '#{block_name}'", self.class.name, node, chain.first)
       end
     elsif node.node_info.has_key?(:thumb) or node.node_info.has_key?(:img)
       ###############################
       # node is a image OR thumbnail
       ###############################
       io = website.blackboard.invoke(:source_paths)[node.node_info[:image_src]].io
       image = Magick::Image.from_blob(io.data).first

       if node.node_info.has_key?(:image_width) and node.node_info.has_key?(:image_height)
         if node.node_info.has_key?(:thumb_resize_method) and node.node_info[:thumb_resize_method] == "cropped"
           image.crop_resized!(node.node_info[:image_width].to_s.to_i, node.node_info[:image_height].to_s.to_i)
         else
           image.resize_to_fit!(node.node_info[:image_width].to_s.to_i, node.node_info[:image_height].to_s.to_i)
         end

         if node.node_info.has_key?(:img)
           # Watermark image using shade
           mark = Magick::Image.new(image.columns, image.rows)
           gc = Magick::Draw.new
           gc.gravity = Magick::SouthEastGravity
           gc.pointsize = 12
           gc.font_family = "Trebuchet MS"
           gc.font_weight = Magick::BoldWeight
           gc.stroke = 'none'
           gc.annotate(mark, 0, 0, 0, 0, "De Mondvermakers")
           mark = mark.shade(true, 310, 30)
           image.composite!(mark, Magick::CenterGravity, Magick::HardLightCompositeOp)
         end
       end

       image.strip! 

       Path::SourceIO.new do 
	     StringIO.new(image.to_blob) { self.quality = 25 }
       end
     elsif node.node_info.has_key?(:collage_img)
       ###########################
       # node is a collage image
       ###########################

       # retrieve images to create collage
       images = []
       images << File.join("src", node.node_info[:collage_image_src0])
       if node.node_info[:collage_image_src1] != nil
         images << File.join("src", node.node_info[:collage_image_src1])
         images << File.join("src", node.node_info[:collage_image_src2])
         images << File.join("src", node.node_info[:collage_image_src3])
       end

       # Create a template image.
       template_width = node.node_info[:collage_image_width].to_s.to_i + 33
       template_height = node.node_info[:collage_image_height].to_s.to_i + 33
       template = Image.new(template_width, template_height) { self.format="PNG" }
       l1 = Image.new(template_width, template_height) { self.background_color = "#dddddd" }
       template.composite!(l1, 0, 0, Magick::OverCompositeOp)
       l2 = Image.new(template_width-3, template_height-113) { self.background_color = "#a3a3a3" }
       template.composite!(l2, 3, 3, Magick::OverCompositeOp)
       l3 = Image.new(template_width-3, template_height-113) { self.background_color = "#ffffff" }
       template.composite!(l3, 0, 0, Magick::OverCompositeOp)

       if images.length > 0
         photo = Image.read("#{images.shift}").first # shift the 1st image off the array (array now contains 3 images for slides)
         photo.crop_resized!(template_width-23, template_height-133)
         template.composite!(photo, 10, 10, Magick::OverCompositeOp)

         if images.length == 3
           (images.size-1).downto(0) do |i|
             slide = create_slide("#{images[i]}")
             template.composite!(slide, i * 100 + rand(15), 150 + rand(15), Magick::OverCompositeOp)
           end
         end
       end

       Path::SourceIO.new do 
	     StringIO.new(template.to_blob) { self.quality = 25 }
       end
     elsif node.node_info.has_key?(:index_img)
       ###########################
       # node is a index image
       ###########################
       index_img_src = node.node_info[:index_image_src]

       if index_img_src != ""
         # Create a index template image.
         index_template_width = 220
         index_template_height = 69
         template = Image.new(index_template_width, index_template_height) { self.format="PNG" }
         l1 = Image.new(index_template_width, index_template_height) { self.background_color = "#ebedeb" }
         template.composite!(l1, 0, 0, Magick::OverCompositeOp)
         l2 = Image.new(index_template_width-2, index_template_height-2) { self.background_color = "#acacac" }
         template.composite!(l2, 2, 2, Magick::OverCompositeOp)
         l3 = Image.new(index_template_width-2, index_template_height-2) { self.background_color = "#ffffff" }
         template.composite!(l3, 0, 0, Magick::OverCompositeOp)

         photo = Image.read(File.join("src", index_img_src)).first
         photo.crop_resized!(index_template_width-10, index_template_height-10)
         template.composite!(photo, 4, 4, Magick::OverCompositeOp)

         Path::SourceIO.new do 
	       StringIO.new(template.to_blob()) { self.quality = 25 }
         end
       end

     end
   end

   ################################################################################################################
   private
   ################################################################################################################

   # Method overridden to lookup parameters specified in the gallery file first.
   def param( name )
     ( @filedata.has_key?( name ) ? @filedata[name] : @defaultfiledata[name] )
   end

   def page_data( metainfo )
     metainfo['lang'] = @filedata['lang']
     temp = metainfo.to_yaml
     temp = "---\n" + temp unless /^---\s*$/ =~ temp
     "#{temp}\n---\n"
   end

   def proper_file_name( name )
     ( name.nil? ? nil : name.tr( '/ .\\\'\,"|', '-' ).downcase )
   end

   def gallery_page_file_name( name )
     ( name.nil? ? nil : 'page_' + proper_file_name( name ) + '.html' )
   end

   def gallery_thumbnail_file_name( name )
     ( name.nil? ? nil : 'tn_' + proper_file_name( name ) + '.jpg' )
   end
  
   def gallery_image_file_name( name )
     ( name.nil? ? nil : proper_file_name( name ) + '.jpg' )
   end

   def create_gallery( images )
     data = (@filedata['galleryPagesMetaInfo'] || {}).dup
     data['template'] ||= param( 'galleryPageTemplate' )
     data['title'] = (data['title'] || @filedata['title'])
     data['description'] = @filedata['description']
     data['collageSize'] = @filedata['collageSize']
     data['mtime'] = @filedata['mtime']

     index_image = create_index_image( images, data )
     collage_image = create_collage_image( images, data )
     g_images = create_image_pages( images )

     gallery = GalleryInfo.new( 'index.html', data, index_image, collage_image, g_images )

     # create nodes for gallery pages
     @g_path.basename = File.basename(gallery.pagename, ".html")
     begin
       page = Webgen::Page.from_data(page_data(gallery.data), @g_path.meta_info)
     rescue Webgen::Page::FormatError => e
       raise Webgen::NodeCreationError.new("Error reading source path: #{e.message}", self.class.name, @g_path)
     end
     @g_path.meta_info = page.meta_info
     @g_path.meta_info['lang'] ||= website.config['website.lang']
     @g_path.ext = 'html'

     create_page_node(@g_path) do |node|
       node.node_info[:page] = page
       node.node_info[:ginfo] = gallery
       @nodes << node
     end

     # create nodes for content pages
     gallery.images.each_with_index do |iData, iIndex|
       @page_path.basename = File.basename(iData.pagename, ".html")
       begin
         page = Webgen::Page.from_data(page_data(iData.data), @page_path.meta_info)
       rescue Webgen::Page::FormatError => e
         raise Webgen::NodeCreationError.new("Error reading source path: #{e.message}", self.class.name, @page_path)
       end
       @page_path.meta_info = page.meta_info
       @page_path.meta_info['lang'] ||= website.config['website.lang']
       @page_path.ext = 'html'

       create_page_node(@page_path) do |node|
         node.node_info[:page] = page
         node.node_info[:ginfo] = gallery
         node.node_info[:iIndex] = iIndex
         @nodes << node
       end
     end

   end

   def create_image_pages( images )
     imageList = []
     images.each_with_index do |image, i|
       data = (@filedata['imagePagesMetaInfo'] || {}).dup
       data.update( @imagedata[image] || {} )
       data['template'] ||= param( 'imagePageTemplate' )
       data['thumbnailSize'] ||= @filedata['thumbnailSize']
       data['thumbnailResizeMethod'] ||= @filedata['thumbnailResizeMethod']
       data['exif'] ||= exif_data( File.join( @src_path, image ) )

       # make sure to have unique filenames
       filename = data['title'] + "_%03d" % i.to_s

       data['thumbnail'] ||= create_thumbnail( image, filename, data )
       image_filename = create_image(image, filename, data)
       image = GalleryInfo::Image.new( gallery_page_file_name(filename), data, image, image_filename )
       imageList << image
     end
     imageList
   end

   def exif_data( image )
     jpeg = EXIFR::JPEG.new( image )
     if !jpeg.nil? && jpeg.exif?
       exif = jpeg.exif.to_hash
       exif[:width] = jpeg.width
       exif[:height] = jpeg.height
       exif[:comment] = jpeg.comment
       exif[:bits] = jpeg.bits
       exif
     else
       nil
     end
   end

   def create_image (image, name, data)
     target_image_path = gallery_image_file_name( name )
     @img_path.basename = target_image_path.gsub(/\.jpg/, '')
     @img_path.ext = 'jpg'
     spath = File.join( File.dirname(@img_path.source_path), image)
    
     if data['exif'][:width] > data['exif'][:height]
       width = 480
       height = 360
     else
       width = 360
       height = 480
     end      
    
     create_page_node(@img_path) do |node|
       node.node_info[:img] = target_image_path
       node.node_info[:image_width] = width
       node.node_info[:image_height] = height
       node.node_info[:image_src] = spath
       @nodes << node
     end
     
     target_image_path
   end

   def create_thumbnail( image, name, data )
     thumb_image_path = gallery_thumbnail_file_name( name )
     @tn_path.basename = thumb_image_path.gsub(/\.jpg/, '')
     @tn_path.ext = 'jpg'
     spath = File.join( File.dirname(@tn_path.source_path), image)

     create_page_node(@tn_path) do |node|
       node.node_info[:thumb] = thumb_image_path
       node.node_info[:thumb_resize_method] = data['thumbnailResizeMethod']
       sizes = data['thumbnailSize'].split(/x/)
       node.node_info[:image_width] = sizes[0]
       node.node_info[:image_height] = sizes[1]
       node.node_info[:image_src] = spath
       @nodes << node
     end

     thumb_image_path
   end

   def create_index_image( images, data )
     index_image_path = "index_" + gallery_image_file_name( data['title'] )
     @index_img_path.basename = index_image_path.gsub(/\.jpg/, '')
     @index_img_path.ext = 'jpg'
     spath = File.join( File.dirname(@index_img_path.source_path), images.first)

     create_page_node(@index_img_path) do |node|
       node.node_info[:index_img] = index_image_path
       node.node_info[:index_image_src] = spath
       @nodes << node
     end
    
     index_image_path
   end

   def create_collage_image( images, data )
     collage_image_path = "collage_" + gallery_image_file_name( data['title'] )
     @collage_img_path.basename = collage_image_path.gsub(/\.jpg/, '')
     @collage_img_path.ext = 'jpg'
     spath = []
     spath << File.join( File.dirname(@collage_img_path.source_path), images.first)
     if images.length > 3
       (1..3).each do |i|
         spath << File.join( File.dirname(@collage_img_path.source_path), images[i])
       end
     end

     create_page_node(@collage_img_path) do |node|
       node.node_info[:collage_img] = collage_image_path
       sizes = data['collageSize'].split(/x/)
       node.node_info[:collage_image_width] = sizes[0]
       node.node_info[:collage_image_height] = sizes[1]
       node.node_info[:collage_image_src0] = spath[0]
       if images.length > 3
         node.node_info[:collage_image_src1] = spath[1]
         node.node_info[:collage_image_src2] = spath[2]
         node.node_info[:collage_image_src3] = spath[3]
       else
         node.node_info[:collage_image_src1] = nil
         node.node_info[:collage_image_src2] = nil
         node.node_info[:collage_image_src3] = nil
       end
       @nodes << node
     end

    collage_image_path
   end

   #############################################################################################
   # helper functions for creating collages
   #############################################################################################

   def create_base_slide()
     # create slide programmatically   
     slide = Image.new(123, 123) { 
       self.format="PNG" 
       self.background_color = 'transparent'
     }

     # Draw border
     d = Magick::Draw.new
     d.fill('white')
     d.stroke('white').stroke_width(1)
     
     d.line(0, 4, 0, 116-1)
     d.line(1, 2, 1, 118-1)

     d.rectangle(2, 1, 4-1, 119-1)
     d.rectangle(4, 0, 16-1, 120-1)

     d.rectangle(16, 0, 104, 16-1)
     d.rectangle(16, 104, 104, 120-1)

     d.line(119, 4, 119, 116-1)
     d.line(118, 2, 118, 118-1)

     d.rectangle(118-1, 1, 116, 119-1)
     d.rectangle(116-1, 0, 104, 120-1)

     # Draw 4 circles
     d.fill('#eeeeee')
     d.stroke('#eeeeee').stroke_width(1)
     d.rectangle(10, 11, 16-1, 15-1)
     d.rectangle(11, 10, 15-1, 16-1)

     d.rectangle(10, 105, 16-1, 109-1)
     d.rectangle(11, 104, 15-1, 110-1)

     d.rectangle(104, 11, 110-1, 15-1)
     d.rectangle(105, 10, 109-1, 16-1)

     d.rectangle(104, 105, 110-1, 109-1)
     d.rectangle(105, 104, 109-1, 110-1)

     # Draw on slide
     d.draw(slide)

     return slide
   end

   def backandforth(degree)
     polarity = rand(2) * -1
     return rand(degree) * polarity if polarity < 0
     return rand(degree)
   end

   def create_slide(image)
     slide = create_base_slide()

     slide_background = Magick::Image.new(slide.columns, slide.rows) { self.background_color = 'transparent' }
     photo = Image.read(image).first
  
     # create a grey scale gradient fill for our mask
     mask_fill = GradientFill.new(0, 0, 0, 88, '#FFFFFF', '#F0F0F0')
     mask = Magick::Image.new(photo.columns, photo.rows, mask_fill)
     # create thumbnail sized square image of photo
     photo.crop_resized!(88,88)

     # apply alpha mask to slide
     photo.matte = true
     mask.matte = false
     photo.composite!(mask, 0, 0, Magick::CopyOpacityCompositeOp)
  
     # composite photo and slide on transparent background
     slide_background.composite!(photo, 16, 16, Magick::OverCompositeOp)
     slide_background.composite!(slide, 0, 0, Magick::OverCompositeOp)
  
     # rotate slide +/- 45 degrees
     rotation = backandforth(45)
     slide_background.rotate!(rotation)
  
     # create workspace to apply shadow
     workspace = Magick::Image.new(slide_background.columns+5, slide_background.rows+5) { self.background_color = 'transparent' }
     shadow = slide_background.shadow(0, 0, 0.0, '20%')
     workspace.composite!(shadow, 3, 3, Magick::OverCompositeOp)
     workspace.composite!(slide_background, Magick::NorthWestGravity, Magick::OverCompositeOp)

     return workspace
   end

end

