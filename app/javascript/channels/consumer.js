// Shared ActionCable consumer. Defaults to the /cable mount; no action-cable-url meta tag
// is needed. Used by the admin panel's live QR / status controller.
import { createConsumer } from "@rails/actioncable"

export default createConsumer()
