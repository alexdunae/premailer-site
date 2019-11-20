# frozen_string_literal: true

$LOAD_PATH.unshift File.dirname(__FILE__)
$stdout.sync = true

require 'rubygems'
require 'bundler'

Bundler.require

require 'premailer_app'

run Sinatra::Application
