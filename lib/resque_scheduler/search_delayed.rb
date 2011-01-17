module ResqueScheduler
  
  def search_delayed_count
    @@search_results.count
  end
  
  def search_delayed(query, start = 0, count = 1)
    if query.nil? || query.empty?
      @@search_results = []
      return []
    end
  
    start, count = [start, count].map { |n| Integer(n) }
    set_results = Set.new

    # For each search term, retrieve the failed jobs that contain at least one relevant field matching the regexp defined by that search term
    query.split.each do |term|
      
      partial_results = []
      self.delayed_queue.find().each do |row|
        row['items'].each do |job|
          if job['class'] =~ /#{term}/i || job['queue'] =~ /#{term}/i
            partial_results << row['_id']
          else
            job['args'].each do |arg|
              arg.each do |key, value|
                if key =~ /#{term}/i || value =~ /#{term}/i
                  partial_results << row['_id']
                end
              end
            end
          end
        end
      end

      # If the set was empty, merge the first results, else intersect it with the current results
      if set_results.empty?
        set_results.merge(partial_results)
      else
        set_results = set_results & partial_results
      end
    end
      
    # search_res will be an array containing 'count' values, starting with 'start', sorted in descending order
    @@search_results = set_results.to_a || []
    search_results = set_results.to_a[start, count]
    search_results || []
  end
end