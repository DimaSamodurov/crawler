require 'capybara'
require_relative 'dsl/sign_in'
require_relative 'dsl/js_helpers'
require_relative 'reports/simple'
require 'pry'

module Crawler
  class Engine
    include Capybara::DSL
    include DSL::SignIn
    include DSL::JsHelpers

    attr_reader :report

    def initialize(save_screenshots_to: nil, max_pages: nil,
                   username: nil, password: nil, window_width: 1024, window_height: 768)

      @screenshots_path = save_screenshots_to
      @username = username
      @password = password
      @max_pages = max_pages.to_i
      @window_width = window_width.to_i
      @window_height = window_height.to_i

      Capybara.save_path = @screenshots_path
      Capybara.run_server = false
      Capybara.register_driver :poltergeist do |app|
        Capybara::Poltergeist::Driver.new(app,
                                          js_errors: false, timeout: 60,
                                          window_size: [@window_width, @window_height] )
      end
      Capybara.default_driver = :poltergeist
      Capybara.ignore_hidden_elements = false

      @report = Reports::Simple.new
      @report.metadata[:screenshots_path] = @screenshots_path
      @report.metadata[:window_width] = @window_width
      @report.metadata[:window_height] = @window_height
    end

    def extract_links(url:)
      uri = URI(url.to_s)
      Capybara.app_host = "#{uri.scheme}://#{uri.host}:#{uri.port}"

      @host_name = uri.host
      @report.start(url: url)
      begin
        signs_in_with(@username, @password) if @username

        crawl(url: url)
      rescue error
        @report.error = error
      ensure
        @report.finish
      end
      self
    end

    def visited_pages
      @report.visited_pages
    end

    private

    def get_page_links
      page.all('a').map do |a|
        href = a['href']
      end
    end

    def internal_url?(url)
      uri = URI(url.to_s)
      return true if uri.host.nil? || uri.host == @host_name
      false
    end

    def limit_reached?
      return false if @max_pages == 0
      return visited_pages.count >= @max_pages
    end

    def crawl(url:)
      return "Skippd external #{url}." unless internal_url?(url)
      return 'Limit reached' if limit_reached?

      uri = URI(url.to_s)
      page_path = uri.path

      return "Skipped visited #{page_path}." if visited_pages.include?(page_path)

      puts "Visiting #{page_path}"

      visit page_path
      wait_for_page_to_load rescue nil

      screenshot_filename = save_screenshot if @screenshots_path

      page_links = get_page_links
      @report.record_page_visit(page: page_path,
                                extracted_links: page_links,
                                screenshot_filename: screenshot_filename)
      @report.pages[page_path] =
        {
          status_code: status_code,
          extracted_links: page_links,
          screenshot: screenshot_filename
        }

      unless limit_reached?
        page_links.each do |href|
          next unless internal_url?(href)
          crawl(url: href)
        end
      end
    rescue => error
      @report.record_page_visit(page: page_path, error: error.message)
      puts "Error visiting #{page_path}: #{error.message}"
    end
  end
end