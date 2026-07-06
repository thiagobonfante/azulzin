module CommitmentsHelper
  # Stable DOM id for a computed occurrence (not an AR record).
  def occurrence_dom_id(occurrence) = "occurrence_#{occurrence.commitment.id}_#{occurrence.month.strftime('%Y%m')}"

  def commitment_schedule_phrase(commitment)
    return "" if commitment.schedule_day.blank?
    t("commitments.row.every_day", day: commitment.schedule_day)
  end

  def occurrence_status_badge(status)
    { paid: "badge-success", posted: "badge-success", presumed_paid: "badge-ghost",
      overdue: "badge-error", due_today: "badge-warning", upcoming: "badge-ghost" }
      .fetch(status, "badge-ghost")
  end
end
