$:.unshift File.dirname(__FILE__)

require 'rubygems'
require 'bundler'

Bundler.require

require 'premailer_app'
run Sinatra::Application
