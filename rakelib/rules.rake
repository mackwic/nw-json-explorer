# -*- coding: utf-8 -*-
require 'slim'
require 'sass'
require 'colored'

unless defined? CONFIG
  raise "You can't run this file directly! Use rake from the root of the project"
end

# coffee {{{
LINTER = './node_modules/coffee-jshint/cli.js'
LINTER_OPTS = CONFIG['coffeejshint']['options'].join ','
LINTER_GLOBALS = CONFIG['coffeejshint']['globals'].join ','
transform :coffee, to: :js do |source, dest|

  opts = [
    "--compile",
  ]

  out = `#{LINTER} -o #{LINTER_OPTS} -g #{LINTER_GLOBALS} #{source}`
  unless out == ""
    puts out.bold.red
    throw 'JSHint error !'
  end

  sh "./node_modules/.bin/coffee #{opts.join ' '} --output #{File.dirname dest} #{source}"
end
# }}}

# js {{{
transform :js, to: :js do |source, dest|
  sh "cp #{source} #{dest}"
end
# }}}

# COPY rules: JS, JSON, Images {{{
COPY_TYPES.each do |ext|
  transform(ext, to: ext) do |src,dest|
    `cp #{src} #{dest}`
  end
end
# }}}

# Silm {{{
Slim::Engine.set_default_options CONFIG['slim'] if CONFIG['slim'].present?

transform :slim, to: :html do |source, dest|
  File.write(dest, Slim::Template.new(source).render)
end
# }}}

# Sass {{{
transform :scss, to: :css do |source, dest|
  if CONFIG['scss']['source_map']
    raise 'FIXME: unsupported source_map !'
    # FIXME: error lors de la résolution du path css <=> scss
    # pour le source_map. Pas le tps de fix -- tw 31/05/14
    #
    #sm_name = dest + CONFIG['scss']['source_map_ext']
    #engine = sass_importer.find(source, {}.merge!(CONFIG['scss']))
    #css, source_map = engine.render_with_sourcemap sm_name
    #File.write(dest, css)
    #File.write(sm_name, source_map.to_json)
  else
    CONFIG['scss'][:load_paths] = CONFIG['scss']['load_paths']
    engine = Sass::Engine.for_file(source, CONFIG['scss'])
    File.write(dest, engine.render)
  end
end
# }}}
