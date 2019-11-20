# frozen_string_literal: true

$LOAD_PATH << File.join(File.dirname(__FILE__), 'lib')
require 'sinatra'
require 'sinatra/reloader' if development?
require 'newrelic_rpm' if production?
require 'haml'
require 'nokogiri'
require 'hpricot'
require 'builder'
require 'json'
require 'digest'
require 'htmlentities'
require 'premailer'
require 'aws-sdk-s3'
require 'rack/throttle'
require 'redis'

use Rack::Throttle::Minute, cache: Redis.new, key_prefix: :throttle

set :show_exceptions, false

@url = ''
AWS_BUCKET = 'premailer'

error do
  e = env['sinatra.error']
  backtrace = "Application error\n#{e}\n#{e.backtrace.join("\n")}"
  warn backtrace
  warn e.inspect

  status 500
  'Sorry there was an error'
end

not_found do
  @message = 'This is nowhere to be found'
  erb :error
end

get '/' do
  @initial_doc = 'https://dialect.ca/premailer-tests/base.html'

  if !params[:bookmarklet].nil?
    do_request
    erb :results
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

get '/api' do
  erb :api
end

post '/api/0.1/documents' do
  content_type 'application/json', charset: 'utf-8'
  opts = {}
  source = nil

  if params[:html] && !params[:html].empty?
    opts[:with_html_string] = true
    source = params[:html]
  elsif params[:url] && !params[:url].empty?
    source = params[:url]
  else
    return 400, [{ message: 'No input file specified', version: '0.1', status: 400 }.to_json]
  end

  opts[:adapter] = :nokogiri
  opts[:base_url] = params[:base_url].strip if params[:base_url]
  opts[:line_length] = params[:line_length].strip.to_i if params[:line_length]
  opts[:link_query_string] = params[:link_query_string].strip if params[:link_query_string]
  opts[:preserve_styles] = params[:preserve_styles] && (params[:preserve_styles] == 'false') ? false : true
  opts[:remove_ids] = params[:remove_ids] && (params[:remove_ids] == 'true') ? true : false
  opts[:remove_classes] = params[:remove_classes] && (params[:remove_classes] == 'true') ? true : false
  opts[:remove_comments] = params[:remove_comments] && (params[:remove_comments] == 'true') ? true : false

  result = process_url(source, opts.merge(io_exceptions: false))

  output = {
    version:   '0.1',
    status:    result[:status].to_i,
    message:   result[:message],
    options:   opts,
    documents: {
      html: result[:output][:html_file],
      txt:  result[:output][:txt_file]
    }
  }

  if output[:status] == 500
    status 500
  else
    response.header['Location'] = result[:output][:html_file]
    expires 7200, :private
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

  if (params[:content_source] == 'html') && !params[:html].empty?
    @opts[:with_html_string] = true
    html = params[:html]
    @source_description = 'your HTML content'
  elsif !params[:url].empty?
    html = params[:url].to_s.strip
    @source_description = html
  else
    @message = 'No input file specified'
    @analytics_page = '/error/no_input'
    erb :error
  end

  @opts[:link_query_string] = params[:querystring].strip if params[:querystring]

  @opts[:preserve_styles] = true if params[:preserve_styles] && (params[:preserve_styles] == 'yes')

  @opts[:remove_ids] = true if params[:remove_ids] && (params[:remove_ids] == 'yes')

  @opts[:remove_classes] = true if params[:remove_classes] && (params[:remove_classes] == 'yes')

  @opts[:remove_comments] = true if params[:remove_comments] && (params[:remove_comments] == 'yes')

  @opts[:adapter] = :nokogiri

  warn "- sending  opts #{@opts.inspect}"

  res = process_url(html, @opts)

  @results = res
  @results
end

def is_valid_api_key?(_api_key)
  true
end

def process_url(url, opts = {})
  @options = { warn_level:        Premailer::Warnings::SAFE,
               text_line_length:  65,
               link_query_string: nil,
               verbose:           true,
               adapter:           :nokogiri }.merge(opts)

  return_status = 201
  message = 'Created'
  warnings = {}
  output = {}

  begin
    warn "- with opts #{@options.inspect}"
    output_base_url = 'http://' + @env['HTTP_HOST'] + '/_out/'

    premailer = Premailer.new(url, @options)
    outfile = generate_request_id(url)

    out_plaintext = premailer.to_plain_text
    out_html = premailer.to_inline_css

    Aws.config.update(
      region:      'us-east-1',
      credentials: Aws::Credentials.new('AKIAJGV6CM4KYKPTRSHA', 'Cd6R8gAyTFRa88wbjbaWUDpDCEa7MITm3qLLYnaq')
    )

    s3 = Aws::S3::Resource.new(region: 'us-east-1')

    text_obj = s3.bucket(AWS_BUCKET).object("#{outfile}.txt")
    text_obj.put(body: out_plaintext, content_type: 'text/plain', acl: 'authenticated-read', expires: Time.now + 7200)

    html_obj = s3.bucket(AWS_BUCKET).object("#{outfile}.html")
    html_obj.put(body: out_html, content_type: 'text/html', acl: 'authenticated-read', expires: Time.now + 7200)

    warnings = premailer.warnings
    output = {
      html_file: html_obj.presigned_url(:get, expires_in: 7200),
      txt_file:  text_obj.presigned_url(:get, expires_in: 7200),
      html:      out_html,
      txt:       out_plaintext
    }

    warn "Saved HTML output to #{output[:html_file]}"
  rescue OpenURI::HTTPError => e
    return_status = 500
    message = 'Source file not found'
  rescue Exception => e
    raise e
    return_status = 500
    message = e.message
  end

  { status:   return_status,
    message:  message,
    url:      url,
    options:  @options,
    warnings: warnings,
    output:   output }
end

def generate_request_id(url)
  Digest::MD5.hexdigest("#{url}#{inspect}#{Time.now}#{rand}")
end
