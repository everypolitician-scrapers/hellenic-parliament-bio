#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'json'
require 'date'
require 'colorize'
require 'rest-client'

require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def current_members
  morph_api_url = 'https://api.morph.io/tmtmtmtm/hellenic-parliament/data.json'
  morph_api_key = ENV["MORPH_API_KEY"]
  result = RestClient.get morph_api_url, params: {
    key: morph_api_key,
    query: "select DISTINCT(id) AS id FROM data WHERE term = '17'"
  }
  JSON.parse(result, symbolize_names: true).map { |r| r[:id] }
end

def noko_for(url)
  Nokogiri::HTML(open(url).read) 
end

def date_from(node)
  return unless node
  Date.parse(node.text.to_s).to_s
end

PERSON_URL = 'http://www.hellenicparliament.gr/en/Vouleftes/Ana-Eklogiki-Perifereia/?MPId=%s'
def scrape_person(mpid)
  url = PERSON_URL % mpid
  noko = noko_for(url)

  contact_box = noko.xpath('//div[@class="box info"][.//h1[.="Contact Info"]]')
  address_types = { 
    'Web Site:' => :website,
    'Email:' => :email,
    'Address:' => :address,
  }
  contacts = Hash[ contact_box.css('dt').map do |dt|
    type = address_types[dt.text] or raise "unknown address type: #{dt.text} in #{url}"
    node = dt.xpath('following-sibling::dt | following-sibling::dd').slice_before { |e| e.name == 'dt' }.first.first
    [type, node]
  end] 

  email = contacts[:email].xpath('a/text()').map { |a| a.text.tidy.gsub(',',';') }.join(";") if contacts[:email]
  website = contacts[:website].xpath('a/@href').map { |t| t.text }.join(';') if contacts[:website]

  data = { 
    id: mpid,
    photo: noko.css('img.inlinephoto/@src').text,

    #TODO also handle versions like http://www.hellenicparliament.gr/en/Vouleftes/Ana-Eklogiki-Perifereia/?MPId=cb78242e-648c-49b5-9087-ccf732ec32c5
    birth_date: date_from(noko.css('dd').find { |dd| dd.text.to_s.include? 'Born on' }),
    email: email,
    website: website,
    # TODO: find phone number in 'address'
    source: url,
  }
  data[:photo] = URI.join(url, URI.encode(data[:photo])).to_s unless data[:photo].to_s.empty?
  ScraperWiki.save_sqlite([:id], data)

end

current_members.each do |member|
  scrape_person(member)
end

