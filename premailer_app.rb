# premailer_app.rb
# ENV["GEM_PATH"] = "/home/dialect/.gems:/home/dialect/.gem:/usr/lib/ruby/gems/1.8"
require 'rubygems'
require 'builder'
require 'logger'
require 'sinatra'
require 'erb'
require 'json'
require 'digest'
require 'premailer'

@url = ''

class MyCustomError < Sinatra::ServerError; end

error MyCustomError do
  status 500
  @message = request.env['sinatra.error'].message
  erb :error
end

get '/' do
  @initial_doc = 'http://' + @env['HTTP_HOST'] + '/tests/base.html'

  if not params[:bookmarklet].nil?
    do_request
  else
    erb :index
  end
end

post '/' do
  do_request
end

get '/feedback' do
  erb :feedback
end

def do_request
  @source_description = ''
  @url = ''  

  if params[:content_source] == 'html' and not params[:html].empty?
    @url = save_html_to_file(params[:html])
    @source_description = 'your HTML content'
  elsif not params[:url].empty?
    @url = params[:url]
    @source_description = @url
  else
    @message = 'No input file specified'
    @analytics_page = '/error/no_input'
    erb :error
  end

  opts = {}

  if params[:querystring]
    opts[:link_query_string] = params[:querystring].strip
  end
  
  res = process_url(@url, opts)

  @results = res

  if res[:status] == 201
    @analytics_page = '/success'
    erb :results
  else
    @message = @results[:message]
    @analytics_page = '/error/processing'
    erb :error
  end
end

def exit_with_error(code, message)
  unless message.nil?
    response['X-Premailer-Message'] = message
  end

  res = {'status' => code,
         'message' => message,
         'url' => @url,
         'output' => nil,
         'request_id' => nil
        }.to_json
  
  body res
  status code.to_i

  finish(res)
end

def api_output(data = {})
  output = {:status => 200, 
   :message => '',
   :url => @url,
   :options => nil,
   :warnings => nil,
   :output => nil,
   :request_id => nil
  }.merge(data)


  if output[:status] == 201
    status 201
  elsif output[:status] == 500
    status 500
  else
    status 200
  end

  body(output.to_json)
end



def is_valid_api_key?(api_key)
  true
end

def process_url(url, opts = {}) 
  @options = {:warn_level => Premailer::Warnings::SAFE,
              :text_line_length => 65, 
              :link_query_string => nil
              }.merge(opts)

  return_status = 201
  message = 'Created'
  warnings = {}
  output = {}

  begin
    output_base_url = 'http://' + @env['HTTP_HOST'] + '/_out/'
    
    premailer = Premailer.new(url, @options)
    outfile = generate_request_id(url)

    out_plaintext = premailer.to_plain_text
    out_html = premailer.to_inline_css

    ftxt = File.open('public/_out/' + outfile + '.txt', "w+")               # write the output file
    ftxt.write(premailer.to_plain_text)
    ftxt.close  

    fout = File.open('public/_out/' + outfile + '.html', "w")              # write the output file
    fout.write(premailer.to_inline_css)
    fout.close

    warnings = premailer.warnings
    output = {
        :html_file => "#{output_base_url}#{outfile}.html",
        :txt_file  => "#{output_base_url}#{outfile}.txt",
        :html => out_html,
        :txt => out_plaintext
      }
  rescue OpenURI::HTTPError => e
    return_status = 500
    message = 'Source file not found'

  rescue Exception => e
    raise e
    return_status = 500
    message = e.message
  end


  {:status => return_status, 
   :message => message,
   :url => url,
   :options => @options,
   :warnings => warnings,
   :output => output
  }
end

def save_html_to_file(html)
  fpath = 'tmp/' +  Digest::MD5.hexdigest(html) + '.html'
  fout = File.open(fpath, "w")
  fout.write(html)
  fout.close
  
  return fpath
end

def generate_request_id(url)
  Digest::MD5.hexdigest("#{url}#{inspect}#{Time.now}#{rand}")
end

