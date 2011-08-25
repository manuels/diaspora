#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.
#

class ShareVisibilitiesController < ApplicationController
  before_filter :authenticate_user!

  def update
    #note :id references a postvisibility
    params[:shareable_id] ||= params[:post_id]
    params[:shareable_type] ||= 'Post'

    @post = Post.where(:id => params[:post_id]).select("id, guid, author_id").first
    @contact = current_user.contact_for(@post.author)

    if @contact && @vis = ShareVisibility.where(:contact_id => @contact.id,
                                                :shareable_id => params[:shareable_id],
                                                :shareable_type => params[:shareable_type]).first
      @vis.hidden = !@vis.hidden
      if @vis.save
        render 'update'
        return
      end
    end
    render :nothing => true, :status => 403
  end
end
