# frozen_string_literal: true

class Visitor < ApplicationRecord
  has_many :events
  belongs_to :user, optional: true

  scope :time_on_site_for_visitor, lambda { |visitor|
                                     select("lower_bounds, upper_bounds")
                                       .from(
                                         Event
                                         .select(
                                           "visitor_id,
              MIN(created_at) AS lower_bounds,
              MAX(created_at) AS upper_bounds"
                                         )
                                         .where(visitor: visitor)
                                         .group(:visitor_id)
                                       )
                                   }

  def self.time_on_site
    select("visitor_id, lower_bounds, upper_bounds")
      .from(
        Event
        .select(
          "visitor_id,
              MIN(created_at) AS lower_bounds,
              MAX(created_at) AS upper_bounds"
        )
        .group(:visitor_id)
      )
      .sort
  end

  def self.total_time_on_site_for_visitor(visitor)
    time_on_site_for_visitor(visitor).sum(
      Arel.sql("EXTRACT(EPOCH FROM (upper_bounds - lower_bounds))")
    )
  end

  def self.average_time_on_site_for_visitor(visitor)
    time_on_site_for_visitor(visitor).average(
      Arel.sql("EXTRACT(EPOCH FROM (upper_bounds - lower_bounds))")
    )
  end

  def self.delete_all_older_than(timestamp)
    destroy_by("created_at < ?", timestamp)
  end
end
