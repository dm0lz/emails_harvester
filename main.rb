require 'selenium-webdriver'
require 'nokogiri'
require 'pdf-reader'
require 'open-uri'
require 'net/http'
require 'logger'
require 'pry'

class EmailHarvester
  def initialize(domain)
    @domain = domain
    @driver = init_driver
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::DEBUG
  end

  def perform
    links = search_results_links
    @logger.info("Fetching #{links.count} results")
    results = emails_from_links(links)
    # binding.pry
    File.write('emails.csv', results.join("\n"))
  rescue StandardError => e
    @logger.fatal(e)
    nil
  ensure
    @driver.quit
  end

  private

  def init_driver
    options = Selenium::WebDriver::Chrome::Options.new # (args: ['headless'])
    driver = Selenium::WebDriver.for(:chrome, options: options)
    driver.manage.timeouts.script_timeout = 40 # seconds
    driver.manage.timeouts.implicit_wait = 40
    driver.manage.timeouts.page_load = 40
    driver
  end

  def retrieve_driver
    @driver.status && @driver
  rescue StandardError
    init_driver
  end

  def emails_from_links(links)
    links.map do |url|
      if url.include?('.pdf')
        scrap_pdf(url)
      else
        html_doc = fetch_page(url)
        search_emails(html_doc) if html_doc
      end
    end.flatten.uniq.compact
  end

  def search_results_links
    search_urls.map do |url|
      search_loop(url)
    end.flatten.uniq.compact
  end

  def search_urls
    base_se_url = 'https://www.bing.com'.freeze
    inbody_search = "#{base_se_url}/search?q=inbody%3A%40#{@domain}&rdr=1&first=1".freeze
    pdf_search = "#{base_se_url}/search?q=#{@domain}+filetype%3apdf&rdr=1&first=1".freeze
    # city_search = "#{base_se_url}/search?q=site%3Ales-villes.fr+%40#{@domain}&rdr=1&first=1".freeze
    [inbody_search, pdf_search]
  end

  def search_loop(url)
    links = []
    result_page = 1
    loop do
      paginated_url = url.sub('first=1', "first=#{result_page}1")
      html_doc = fetch_page(paginated_url)
      break if html_doc.to_s.include?('Aucun résultat pour')

      links << parse_links(html_doc)
      result_page += 1
    end
    links
  end

  def fetch_page(url)
    @driver = retrieve_driver
    @driver.get(url)
    search_results = @driver.page_source
    Nokogiri.HTML5(search_results)
  rescue StandardError => e
    @driver.quit
  end

  def parse_links(doc)
    doc.css('li > h2 > a').map do |item|
      item.to_s.match(/href="(.*?)"/)[1]
    rescue StandardError => e
      @logger.fatal(e)
      nil
    end
  end

  def search_emails(doc)
    reg_str = '\b' + '[A-Za-z0-9._%+-]+@' + @domain.split('.').join('\\.') + '\b'
    email_regexp = Regexp.new(reg_str)
    emails = doc.to_s.scan(email_regexp)
    @logger.info(emails)
    emails
  rescue StandardError => e
    @logger.fatal(e)
    nil
  end

  def scrap_pdf(url)
    @logger.info("Scraping PDF from #{url}")
    io = URI.open(url, ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE, 'User-Agent' => 'safari')
    reader = PDF::Reader.new(io)
    text = reader.pages.map(&:text)
    search_emails(text)
  rescue StandardError => e
    @logger.fatal(e)
    nil
  end
end

domain = 'france2.fr'
EmailHarvester.new(domain).perform
