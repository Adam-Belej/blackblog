require 'execjs'
require 'digest'
require 'htmlentities'

PATH_TO_JS = "./_plugins/katex.min.js"
PATH_TO_CACHE_DIR = "./.jekyll-cache/katex-cache/"
KATEX = ExecJS.compile(open(PATH_TO_JS).read)
PARSE_ERROR_PLACEHOLDER = "<b style='color: red;'>PARSE ERROR</b>"
$global_macros = Hash.new
$count_newly_generated_expressions = 0
$count_cached_expressions = 0

def convert(doc)
  # convert HTML enetities back to characters
  post = HTMLEntities.new.decode(doc.to_s)
  post = post.gsub(/(\\\()((.|\n)*?)(?<!\\)\\\)/) { |m| escape_method($1, $2, doc.path) }
  post = post.gsub(/(\\\[)((.|\n)*?)(?<!\\)\\\]/) { |m| escape_method($1, $2, doc.path) }
  return post
end

def escape_method( type, string, doc_path )
  @display = false

  # detect if expression is display view
  case type.downcase
    when /\(/
      @display = false
    else /\[/
      @display = true
  end

  # generate a hash from the math expression
  @hash = Digest::SHA2.hexdigest string
  @cache_path = PATH_TO_CACHE_DIR + @hash + @display.to_s

  # use it if it exists
  if(File.exist?(@cache_path))
    $count_cached_expressions += 1
    print_stats
    return File.read(@cache_path)

  # else generate one and store it
  else
    # create the cache directory, if it doesn't exist
    @cache_dir_path = File.dirname(@cache_path)
    Dir.mkdir(@cache_dir_path) unless Dir.exist?(@cache_dir_path)

    begin
      # render using ExecJS
      @result =  KATEX.call("katex.renderToString", string, 
                          {displayMode: @display,  macros: $global_macros})
    rescue SystemExit, Interrupt
      # this stops jekyll being immune to interupts and kill command
      raise
    rescue Exception => e
      # Catch parse error
      puts "\e[31m " + e.message.gsub("ParseError: ", "") + "\n\t"  + doc_path + "\e[0m"
      return PARSE_ERROR_PLACEHOLDER
    end
    # save to cache
    File.open(@cache_path, 'w') { |file| file.write(@result) }
    # update count of newly generated expressions
    $count_newly_generated_expressions += 1
    print_stats
    return @result
  end
end

def print_stats
  print "             LaTeX: " + 
        ($count_newly_generated_expressions + $count_cached_expressions).to_s + 
        " expressions rendered (" + $count_cached_expressions.to_s + 
        " already cached)        \r"
  $stdout.flush
end

Jekyll::Hooks.register :documents, :post_render do |doc|
  doc.output = convert(doc)
end

Jekyll::Hooks.register :site, :after_init do |site|
  # load macros from config file
  if site.config["latex-macros"] != nil
    for macro_definition in site.config["latex-macros"]
      $global_macros[macro_definition[0]] = macro_definition[1]
    end
  end
  # print macro informaion
  if $global_macros.size == 0
    puts "             LaTeX: no macros loaded"
  else
    puts "             LaTeX: " + $global_macros.size.to_s + " macro" + 
          ($global_macros.size == 1 ? "" : "s") + " loaded"
  end
end

Jekyll::Hooks.register :site, :after_reset do
  # reset counts after reset
  $count_newly_generated_expressions = 0
  $count_cached_expressions = 0
end

Jekyll::Hooks.register :site, :post_write do
  # print new line to prevent overwriting previous output
  print "\n"
end
