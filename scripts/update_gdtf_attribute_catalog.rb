#!/usr/bin/env ruby

require "rexml/document"

source = ARGV.fetch(0)
target = ARGV.fetch(1, "apps/web/lib/src/gdtf_attribute_catalog.g.dart")
document = REXML::Document.new(File.read(source))

escape = lambda do |value|
  value.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'")
end

rows = []
REXML::XPath.each(document, "//Attributes/Attribute") do |attribute|
  rows << [
    attribute.attributes["Name"],
    attribute.attributes["Pretty"] || attribute.attributes["Name"],
    attribute.attributes["Feature"] || "Control.Control",
  ]
end

output = <<~DART
  // Generated from the canonical GDTF 1.2 AttributeDefinitions.xml.
  // Source: https://github.com/open-stage/python-gdtf/blob/master/AttributeDefinitions.xml
  // Run scripts/update_gdtf_attribute_catalog.rb to refresh this file.
  part of 'gdtf_attribute_catalog.dart';

  const gdtfAttributeCatalog = <GdtfAttributeDefinition>[
DART

rows.each do |name, pretty, feature|
  output << "  GdtfAttributeDefinition(name: '#{escape.call(name)}', pretty: '#{escape.call(pretty)}', feature: '#{escape.call(feature)}'),\n"
end
output << "];\n"

File.write(target, output)
puts "Wrote #{rows.length} GDTF attributes to #{target}"
