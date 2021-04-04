
class TiddlywikiController < ApplicationController
  layout false

  before_action :find_site

  # TiddlyWiki can't provide the token for saving so we need to skip it
  skip_before_action :verify_authenticity_token, only: :save

  # Rails wants a token for options requests, which TiddlyWiki similarly can't provide
  skip_before_action :verify_authenticity_token,
    only: [:serve, :json_content, :tid_content],
    if: -> { request.options? }

  # For now CORS is supported for only these two requests
  before_action :cors_headers, only: [:json_content, :tid_content]

  def serve
    return site_not_available unless site_visible?

    # Avoid site download for head or options requests
    return head 200 if request.head? || request.options?

    # Don't serve a file if it doesn't resemble a valid TiddlyWiki
    return site_not_valid unless site_valid?

    update_view_count_and_access_timestamp

    render html: @site.html_content.html_safe
  end

  def json_content
    return site_not_available unless site_visible?

    # Return empty body for options request with CORS headers
    return head 200 if request.options?

    include_system = params[:include_system] == '1'
    skinny = params[:skinny] == '1'
    title = params[:title]
    pretty = params[:pretty] == '1'

    json_data = @site.json_data(include_system: include_system, skinny: skinny)

    json_data = json_data.select { |d| Array.wrap(title).include?(d['title']) } if title.present?

    # I guess...
    update_view_count_and_access_timestamp

    render json: pretty ? JSON.pretty_generate(json_data) : json_data.to_json
  end

  def tid_content
    return site_not_available unless site_visible?

    title = params[:title]
    tiddler_data = @site.tiddler_data(title)

    # If we get nil, assume the tiddler doesn't exist
    return head 404 unless tiddler_data

    # Return empty body for options request with CORS headers
    return head 200 if request.options?

    # Otherwise render it in .tid format
    render plain: tiddler_data_to_tid_text(tiddler_data)
  end

  def favicon
    # It probably doesn't matter much about the favicon, but
    # let's make its availability the same as the site
    return site_not_available unless site_visible?

    send_favicon(@site.favicon_asset_name)
  end

  def download
    return site_not_available unless site_downloadable?

    # Downloads count as a view
    update_view_count_and_access_timestamp

    download_html_content(@site.download_content, @site.name)
  end

  def save
    begin
      if site_saveable?
        @site.tiddlywiki_file.attach(params[:userfile])
        render plain: "0 - OK\n"
      else
        # Give a 200 status no matter what so the user sees the message in a browser alert
        render plain: "If this is your site please log in at\n#{main_site_url} and try again.\n"
      end
    rescue => e
      # Todo: Should probably give a generic "Save failed!" message, and log the real problem
      render plain: "#{e.class.name} - #{e.message}\n"
    end
  end

  private

  def update_view_count_and_access_timestamp
    # Don't count admin clicks on other users' sites
    return if user_is_admin? && !user_owns_site?

    # Don't count views by site owner
    @site.increment_view_count unless user_owns_site?

    # Do count accesses by owner (or anyone else)
    @site.increment_access_count

    # Always touch the timestamp
    @site.touch_accessed_at
  end

  def site_not_valid
    @status_code, @status_message = [418, 'Invalid TiddlyWiki']
    render :site_not_available, status: @status_code, layout: 'simple'
  end

  def site_not_available
    @status_code, @status_message = site_not_available_status

    # Send an empty body for favicon and download actions
    return head @status_code if action_name != "serve"

    # When serving the site, send the "not available" page
    render :site_not_available, status: @status_code, layout: 'simple'
  end

  def site_not_available_status
    # Site doesn't exist
    return [404, 'Not Found'] unless site_exists?

    # User signed in, site unavailable
    return [403, 'Unauthorized'] if user_signed_in?

    # User not signed in, site unavailable
    [401, 'Forbidden']
  end

  def site_visible?
    site_exists? && (site_public? || user_owns_site? || user_is_admin?)
  end

  def site_downloadable?
    site_visible?
  end

  def site_saveable?
    site_exists? && user_owns_site?
  end

  def user_owns_site?
    user_signed_in? && current_user == @site.user
  end

  def site_exists?
    @site.present?
  end

  def site_public?
    @site.is_public?
  end

  def site_valid?
    # Beware this requires downloading the site's content
    @site.looks_valid?
  end

  def find_site
    site_name = request.subdomain
    @site = Site.find_by_name(site_name)
  end

  def tiddler_data_to_tid_text(tiddler_data)
    [
      tiddler_data.except('text').sort_by{ |k, v| k}.map{ |k, v| "#{k}: #{v}\n" },
      "\n",
      tiddler_data['text'],
      "\n",
    ].flatten.join
  end

  # So browsers are permitted to do fetches from different domains
  def cors_headers
    response.set_header 'Access-Control-Allow-Origin', '*'
    response.set_header 'Access-Control-Request-Method', 'GET'
    response.set_header 'Access-Control-Allow-Headers', 'X-Requested-With'
  end

end
