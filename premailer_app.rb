$: << File.join(File.dirname(__FILE__), 'lib')
require 'sinatra'
require "sinatra/reloader" if development?
require 'haml'
require 'nokogiri'
require 'builder'
require 'json'
require 'digest'
require 'datamapper'
require 'dm-migrations'
require 'dm-sqlite-adapter' if development?
#require 'dm-postgres-adapter' if production?
require 'premailer'
require 'aws/s3'


# DataMapper.setup(:default, ENV['DATABASE_URL'] || 'sqlite3://premailer.db')
# 
# class Action
#   include DataMapper::Resource
#   
#   property :id,        Serial
#   property :name,      String
#   property :source,    String
#   property :url,       String
#   property :body,      Text      
#   property :options,   String
#   property :created_at, DateTime
# end
# DataMapper.finalize
# Action.auto_migrate!
#

@url = ''
AWS_BUCKET = 'premailer'

error do
  'Sorry there was a nasty error - ' + env['sinatra.error'].name
end

not_found do
  @message = 'This is nowhere to be found'
  erb :error
end

get '/' do
  @initial_doc = 'http://dialect.ca/premailer-tests/base.html'

  if not params[:bookmarklet].nil?
    do_request
  else
    erb :index
  end
end

post '/' do
  res = do_request
  
  if res[:status] == 201
    @analytics_page = '/success'
    erb :results
  else
    @message = @results[:message]
    @analytics_page = '/error/processing'
    erb :error
  end
  
end

post '/api' do
  res = do_request
  output = {
    :status => res[:status], 
    :message => res[:message],
    :warnings => nil,
    :output => {
      :html => res[:output][:html_file],
      :txt => res[:output][:txt_file],
    }
  }

  if output[:status] == 500
    status 500
  else
    status 201
  end

  body(output.to_json)
end

get '/feedback' do
  erb :feedback
end

def do_request
  @source_description = ''
  @html = ''  

  @opts = {}

  if params[:content_source] == 'html' and not params[:html].empty?
    @opts[:with_html_string] = true
    html = params[:html]
    @source_description = 'your HTML content'
  elsif not params[:url].empty?
    html = params[:url]
    @source_description = html
  else
    @message = 'No input file specified'
    @analytics_page = '/error/no_input'
    erb :error
  end

  if params[:querystring]
    @opts[:link_query_string] = params[:querystring].strip
  end
  
  if params[:preserve_styles] and params[:preserve_styles] == 'yes'
    @opts[:preserve_styles] = true
  end

  if params[:remove_ids] and params[:remove_ids] == 'yes'
    @opts[:remove_ids] = true
  end

  if params[:remove_classes] and params[:remove_classes] == 'yes'
    @opts[:remove_classes] = true
  end
  
  if params[:remove_comments] and params[:remove_comments] == 'yes'
    @opts[:remove_comments] = true
  end

  res = process_url(html, @opts)

  # @post = Action.create(
  #   :name      => 'premailer',
  #   :source    => 'form',
  #   :url       => params[:url],
  #   :body      => params[:html],
  #   :options   => opts
  # )

  @results = res
  @results
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



def is_valid_api_key?(api_key)
  true
end

def process_url(url, opts = {}) 
  @options = {:warn_level => Premailer::Warnings::SAFE,
              :text_line_length => 65, 
              :link_query_string => nil,
              :verbose => true,
              :adapter => :hpricot
              }.merge(opts)

  return_status = 201
  message = 'Created'
  warnings = {}
  output = {}

  begin
    $stderr.puts "Processing #{url} with opts #{@options.inspect}"
    output_base_url = 'http://' + @env['HTTP_HOST'] + '/_out/'
    
    premailer = Premailer.new(url, @options)
    outfile = generate_request_id(url)

    out_plaintext = premailer.to_plain_text
    out_html = premailer.to_inline_css

    AWS::S3::Base.establish_connection!(
      :access_key_id     => 'AKIAJGV6CM4KYKPTRSHA',
      :secret_access_key => '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'
    )

    AWS::S3::S3Object.store("#{outfile}.txt", premailer.to_plain_text, AWS_BUCKET, :content_type => 'text/plain; charset=utf-8', :access => :authenticated_read)
    AWS::S3::S3Object.store("#{outfile}.html", premailer.to_inline_css, AWS_BUCKET, :content_type => 'text/html; charset=utf-8', :access => :authenticated_read)

    # keep the URLs up for two hours
    ftxt = AWS::S3::S3Object.url_for(outfile + '.txt', AWS_BUCKET, :use_ssl => true, :expires_in => 7200)
    fhtml = AWS::S3::S3Object.url_for(outfile + '.html', AWS_BUCKET, :use_ssl => true, :expires_in => 7200)

    warnings = premailer.warnings
    output = {
        :html_file => fhtml,
        :txt_file  => ftxt,
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

def generate_request_id(url)
  Digest::MD5.hexdigest("#{url}#{inspect}#{Time.now}#{rand}")
end

