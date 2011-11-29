require 'texticle/full_text_index'
require 'texticle/railtie' if defined?(Rails) and Rails::VERSION::MAJOR > 2

####
# Texticle exposes full text search capabilities from PostgreSQL, and allows
# you to declare full text indexes.  Texticle will extend ActiveRecord with
# named_scope methods making searching easy and fun!
#
# Texticle.index is automatically added to ActiveRecord::Base.
#
# To declare an index on a model, just use the index method:
#
#   class Product < ActiveRecord::Base
#     index do
#       name
#       description
#     end
#   end
#
# This will allow you to do full text search on the name and description
# columns for the Product model.  It defines a named_scope method called
# "search", so you can take advantage of the search like this:
#
#   Product.search('foo bar')
#
# Indexes may also be named.  For example:
#
#   class Product < ActiveRecord::Base
#     index 'author' do
#       name
#       author
#     end
#   end
#
# A named index will add a named_scope with the index name prefixed by
# "search".  In order to take advantage of the "author" index, just call:
#
#   Product.search_author('foo bar')
#
# Parameters to the index method can also be specified as a hash, e.g.
#   class Product < ActiveRecord::Base
#     index :name => 'author', :normalization => 1 do
#      ...
#
# The available options are:
#   - :name
#     as explained above
#   - :dictionary
#     determines which configuration to use. Defaults to 'english'
#   - :key_column
#     sets the column that will be distinct in case of a unique_search
#   - :normalization
#     sets the normalization strategy, which enables taking into account the document length
#     see http://www.postgresql.org/docs/9.0/interactive/textsearch-controls.html#TEXTSEARCH-RANKING
#     for an explanation. Defaults to 0
#   - :limit
#     sets a limit for any temporary tables used by the search query. Only used by unique_search. Defaults to 1000
#
# Finally, column names can be ranked.  The ranks are A, B, C, and D.  This
# lets us declare that matches in the "name" column are more important
# than matches in the "description" column:
#
#   class Product < ActiveRecord::Base
#     index do
#       name          'A'
#       description   'B'
#     end
#   end
#
# Rank weight values can be specified as follows:
#
# #   class Product < ActiveRecord::Base
#     index do
#       name          'A' => 0.9
#       description   'B' => 0.3
#     end
#   end
#
# Postgresql assigns default weight values of A => 1.0, B => 0.4, C => 0.2 and D => 0.1.
#

module Texticle

  # A list of full text indexes
  attr_accessor :full_text_indexes

  ###
  # Create an index with +name+ using +dictionary+
  def index name = nil, dictionary = nil, options = {}, &block
    options, name = name, options[:name] if name.respond_to? :keys
    name ||= options[:name]
    dictionary ||= options[:dictionary] || 'english'
    options = {:key_column => nil, :limit => 1000, :normalization => 0}.merge(options)

    search_name = ['search', name].compact.join('_')
    index_name  = [table_name, name, 'fts_idx'].compact.join('_')
    this_index  = FullTextIndex.new(index_name, dictionary, self, &block)
    limit = options[:limit].to_i
    normalization = options[:normalization].to_i

    (self.full_text_indexes ||= []) << this_index

    scope_lambda = lambda { |term|
      # Let's extract the individual terms to allow for quoted and wildcard terms.
      term = term.scan(/"([^"]+)"|(\S+)/).flatten.compact.map do |lex|
        lex =~ /(.+)\*\s*$/ ? "'#{$1}':*" : "'#{lex}'"
      end.join(' & ')

      {
        :select => "#{table_name}.*, ts_rank_cd(#{this_index.weights},(#{this_index.to_s}),
          to_tsquery(#{connection.quote(dictionary)}, #{connection.quote(term)}), #{normalization}) as rank",
        :conditions =>
          ["#{this_index.to_s} @@ to_tsquery(?,?)", dictionary, term],
        :order => 'rank DESC'
      }
    }

    key_column = options[:key_column]
    if key_column.present?
      # Selects rows that are unique in "key_column", including only the row with the highest ranking
      unique_scope_lambda = lambda { |term|
        term = term.scan(/"([^"]+)"|(\S+)/).flatten.compact.map do |lex|
          lex =~ /(.+)\*\s*$/ ? "'#{$1}':*" : "'#{lex}'"
        end.join(' & ')

        {
          :select => "_rank_table.*",
          :from => "(SELECT *, ts_rank_cd(#{this_index.weights},(#{this_index.to_s}),
            to_tsquery(#{connection.quote(dictionary)}, #{connection.quote(term)}), #{normalization}) as rank,
            row_number() OVER rank_group AS row_num,
            count(*) over rank_group AS cnt
            FROM #{table_name}
            WHERE #{this_index.to_s} @@ to_tsquery(#{connection.quote(dictionary)}, #{connection.quote(term)})
            WINDOW rank_group AS (
              PARTITION BY #{table_name}.#{key_column}
              ORDER BY ts_rank_cd(#{this_index.weights}, (#{this_index.to_s}),
                to_tsquery(#{connection.quote(dictionary)}, #{connection.quote(term)}), #{normalization}) DESC
            )
            ORDER BY rank DESC
            LIMIT #{limit}
            ) AS _rank_table",
          :conditions => "row_num = 1",
          :order => 'rank DESC'
        }
      }
    end

    # tsearch, i.e. trigram search
    trigram_scope_lambda = lambda { |term|
      term = "'#{term.gsub("'", "''")}'" # " because emacs ruby-mode is totally confused by this line


      similarities = this_index.index_columns.values.flatten.inject([]) do |array, index|
        array << "similarity(#{index}, #{term})"
      end.join(" + ")

      conditions = this_index.index_columns.values.flatten.inject([]) do |array, index|
        array << "(#{index} % #{term})"
      end.join(" OR ")

      {
        :select => "#{table_name}.*, #{similarities} as rank",
        :conditions => conditions,
        :order => 'rank DESC'
      }
    }

    class_eval do
      # Trying to avoid the deprecation warning when using :named_scope
      # that Rails 3 emits. Can't use #respond_to?(:scope) since scope
      # is a protected method in Rails 2, and thus still returns true.
      if self.respond_to?(:scope) and not protected_methods.include?('scope')
        scope search_name.to_sym, scope_lambda
        scope(('unique_' + search_name).to_sym, unique_scope_lambda)
        scope(('t' + search_name).to_sym, trigram_scope_lambda)
      elsif self.respond_to? :named_scope
        named_scope search_name.to_sym, scope_lambda
        named_scope(('unique_' + search_name).to_sym, unique_scope_lambda)
        named_scope(('t' + search_name).to_sym, trigram_scope_lambda)
      end
    end
  end
end
