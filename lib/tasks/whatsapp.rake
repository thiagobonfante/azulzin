namespace :whatsapp do
  desc "Per-modality WhatsApp capture health (park/correction/undo rates). SINCE_DAYS=90"
  task capture_stats: :environment do
    since = Integer(ENV["SINCE_DAYS"] || 90).days.ago
    puts "WhatsApp capture stats since #{since.to_date} (floor #{Whatsapp::Confidence.floor})"
    Whatsapp::CaptureStats.call(since: since).each do |source, s|
      puts "\n#{source}: #{s[:total]} scored"
      next if s[:total].zero?
      puts "  auto-posted #{s[:auto_posted]} · parked #{s[:parked]} · asked #{s[:asked]} · avg confidence #{s[:avg_confidence]}"
      puts "  corrections on auto-posted: amount #{s[:amount_corrected]} · merchant #{s[:merchant_corrected]} · undone #{s[:undone]}"
    end
  end
end
