CREATE TABLE `billing_session_entitlement_grant` (
  `id` text PRIMARY KEY NOT NULL,
  `session_id` text NOT NULL REFERENCES `session`(`id`),
  `purchase_chain_id` text NOT NULL REFERENCES `billing_purchase_chain`(`id`),
  `entitlement_id` text NOT NULL,
  `source` text NOT NULL,
  `status` text NOT NULL,
  `granted_at` text NOT NULL,
  `expires_at` text,
  `last_verified_at` text NOT NULL,
  `revoked_at` text,
  `updated_at` text NOT NULL,
  CONSTRAINT `uq_billing_session_grant_session_chain_entitlement` UNIQUE(`session_id`, `purchase_chain_id`, `entitlement_id`),
  CONSTRAINT `ck_billing_session_grant_status` CHECK (`status` IN ('active', 'revoked', 'expired'))
);
--> statement-breakpoint
CREATE INDEX `idx_billing_session_grant_session_status_expiry`
ON `billing_session_entitlement_grant` (`session_id`, `entitlement_id`, `status`, `expires_at`);
--> statement-breakpoint
CREATE INDEX `idx_billing_session_grant_chain_status`
ON `billing_session_entitlement_grant` (`purchase_chain_id`, `status`);
