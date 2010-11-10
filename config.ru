require '/home/dialect/.gems/gems/rack-0.9.1/lib/rack.rb'
require '/home/dialect/.gems/gems/sinatra-0.9.2/lib/sinatra.rb'
APP_PATH = '/home/dialect/premailer'

ENV['GEM_PATH'] = '/home/dialect/.gems:/home/dialect/.gem:/usr/lib/ruby/gems/1.8'
ENV['PATH'] = APP_PATH + ':' + APP_PATH + '/lib:' + ENV['PATH']

#require 'rubygems'
#require 'sinatra'

Sinatra::Application.default_options.merge!(
  :root => APP_PATH,
  :public => APP_PATH + '/public',
  :views => '/home/dialect/premailer/views/',
  :run => false,
  :env => :production,
  :raise_errors => true
)
dt = Time.new.strftime('%Y-%m-%d')
log = File.new("/home/dialect/premailer/logs/sinatra-#{dt}.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)

require 'premailer_app'
run Sinatra::Application
