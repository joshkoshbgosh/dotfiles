export const OpenCodeAlerts = async ({ project, client, $, directory, worktree }) => {
  return {
    event: async ({ event }) => {
      const eventType = event.type
      const sessionTitle = event.sessionTitle || ""

      if (eventType === "permission.asked") {
        const info = event.info || {}
        const message = info.tool ? `Tool: ${info.tool}` : "Permission requested"
        await $`opencode-alert permission "${sessionTitle}: ${message}"`
      }

      if (eventType === "session.idle") {
        await $`opencode-alert complete "${sessionTitle}"`
      }

      if (eventType === "session.error") {
        const errorMsg = event.error || "Session error"
        await $`opencode-alert error "${sessionTitle}: ${errorMsg}"`
      }
    },
  }
}
