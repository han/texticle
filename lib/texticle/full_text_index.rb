module Texticle
  class FullTextIndex # :nodoc:
    attr_accessor :index_columns

    DEFAULT_WEIGHTS = {'D' => 0.1, 'C' => 0.2, 'B' =>  0.4, 'A' => 1.0}

    def initialize name, dictionary, model_class, &block
      @name           = name
      @dictionary     = dictionary
      @model_class    = model_class
      @index_columns  = {}
      @string         = nil
      @weight_values = DEFAULT_WEIGHTS.clone
      instance_eval(&block)

    end

    def self.find_constant_of(filename)
      File.basename(filename, '.rb').pluralize.classify.constantize
    end

    def create
      @model_class.connection.execute create_sql
    end

    def destroy
      @model_class.connection.execute destroy_sql
    end

    def create_sql
      <<-eosql.chomp
CREATE index #{@name}
      ON #{@model_class.table_name}
      USING gin((#{to_s}))
      eosql
    end

    def destroy_sql
      "DROP index IF EXISTS #{@name}"
    end

    def to_s
      return @string if @string
      vectors = []
      @index_columns.sort_by { |k,v| k }.each do |weight, columns|
        c = columns.map { |x| "coalesce(\"#{@model_class.table_name}\".\"#{x}\", '')" }
        if weight == 'none'
          vectors << "to_tsvector('#{@dictionary}', #{c.join(" || ' ' || ")})"
        else
          vectors <<
        "setweight(to_tsvector('#{@dictionary}', #{c.join(" || ' ' || ")}), '#{weight}')"
        end
      end
      @string = vectors.join(" || ' ' || ")
    end

    def weights
      "array[#{%w{D C B A}.each.map {|k| @weight_values[k]}.join(',')}]"
    end

    def method_missing name, *args
      weight = args.shift || 'none'
      if weight.respond_to? :keys
        key = weight.keys[0]
        if %w{A B C D}.include? key
          @weight_values[key] = weight[key]
          weight = key
        end
      end
      (index_columns[weight] ||= []) << name.to_s
    end

  end
end
