require 'httparty'
require 'nokogiri'
require 'byebug'

def scraper
  url = 'https://github.com/marketplace?category=&query=&type=apps&verification='
  unparsed_page = HTTParty.get(url)
  parsed_page = Nokogiri::HTML(unparsed_page)
  app_listings = parsed_page.css('a.col-md-6') # get all listings from one page
  apps = [] # array of hashes
  page = 1
  per_page = app_listings.count
  total = parsed_page.at('span.text-bold').text.split[0].to_i
  last_page = (total.to_f / per_page.to_f).ceil
  while page <= last_page
    pagination_url = "https://github.com/marketplace?category=&page=#{page}&query=&type=apps&verification="
    pagination_unparsed_page = HTTParty.get(pagination_url)
    pagination_parsed_page = Nokogiri::HTML(pagination_unparsed_page)
    pagination_app_listings = pagination_parsed_page.css('a.col-md-6')
    pagination_app_listings.each do |app_listing|
      app = {
        page: page,
        title: app_listing.at('h3').text.strip,
        short_desc: app_listing.css('p.color-fg-muted').text.split.drop(2).join(' '),
        app_url: "https://github.com" + "#{app_listing.attributes['href'].value}",
        installs: app_listing.css('span').text.strip.gsub(" installs","")
      }
      apps << app
    end
    CSV.open("github_apps_all.csv", "w") do |csv|
      keys = apps.flat_map(&:keys).uniq
        apps.each do |row|
          csv << row.values_at(*keys)
        end
    end
    page += 1
    sleep 5
  end
end

# scrape data from app details pages e.g. https://github.com/marketplace/rollbar
def enrich
  File.open("github_apps_urls_july.csv", "r") do |file|
    file.each do |url|
      uri = URI(url.strip)
      unparsed_page = HTTParty.get(uri)
      parsed_page = Nokogiri::HTML(unparsed_page)
      apps = []
      categories = []
      exclude = ["Free", "Paid", "Free Trials", "GitHub Enterprise", "Recently added"]
      categories_section = parsed_page.at('li.pt-3.pb-3.lh-condensed').css('a.topic-tag.topic-tag-link.f6')
      categories_section.each do |category|
        categories << category.children.text.strip
      end
      categories_cleaned = categories - exclude
      pricing_plans = []
      pricing_table = parsed_page.at('div.col-md-6.float-md-left.pr-md-6.mb-4.mb-md-0').css('ul.filter-list.ml-md-n3.mr-md-n3')
      pricing_table.each do |plan| # rozdzielic na osobne hashe na kazdy plan
        pricing_plan = {
          plan_name: plan.css('h4.f3.d-inline-block.marketplace-plan-emphasis').text.strip,
          plan_price: plan.css('div.text-small').css('span.f3.marketplace-plan-emphasis').text,
          plan_limit: plan.css('p.text-small.mb-0.pr-2').text
        }
      pricing_plans << pricing_plan
      end
      tos_url = parsed_page.css('li.py-3.lh-condensed').css('li.mb-1').css('a')[-2].attributes['href'].value
      free = categories.include? "Free"
      paid = categories.include? "Paid"
      trial = categories.include? "Free Trials"
      enterprise = categories.include? "GitHub Enterprise"
      app = {
        url: url,
        logo_url: parsed_page.at('img.CircleBadge-icon').attributes['src'].value,
        developer_name: parsed_page.at('a.d-flex.flex-items-center.css-truncate.css-truncate-target').children.text.strip,
        developer_github_url: "https://github.com" + "#{parsed_page.at('a.d-flex.flex-items-center.css-truncate.css-truncate-target')['href']}",
        developer_url: "https://" + "#{URI(tos_url).host}",
        categories_cleaned: categories_cleaned.to_s,
        free: free,
        paid: paid,
        trial: trial,
        enterprise: enterprise,
        pricing_plans: pricing_plans
      }
      apps << app
        CSV.open("github_apps_details.csv", "a+") do |csv|
          keys = apps.flat_map(&:keys).uniq
            apps.each do |row|
              csv << row.values_at(*keys)
            end
        end
        sleep 8
      end
    end
  end
