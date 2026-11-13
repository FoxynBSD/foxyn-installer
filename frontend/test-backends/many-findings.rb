#!/usr/bin/env ruby
require 'json'
puts JSON.generate('version'=>1,'id'=>1,'result'=>{'findings'=>(1..20).map { |n| {'message'=>"Hardware finding #{n}: example device requires attention."} }})
