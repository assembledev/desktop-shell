import QtQuick
import Quickshell

QtObject {
  id: root

  readonly property string outputName: Quickshell.env("DESKTOP_SHELL_OUTPUT")
  readonly property var screen: {
    const screens = Quickshell.screens || [];
    if (outputName.length > 0) {
      const configured = screens.find(function(candidate) {
        return String(candidate?.name || "") === outputName;
      });
      if (configured)
        return configured;
      console.warn("desktop-shell: configured output is unavailable: " + outputName);
    }
    return screens.length > 0 ? screens[0] : null;
  }

  readonly property var workspaces: {
    const raw = Quickshell.env("DESKTOP_SHELL_WORKSPACES_JSON");
    try {
      const parsed = JSON.parse(raw || "[]").filter(function(item) {
        return Number.isInteger(Number(item?.id)) && Number(item.id) > 0;
      }).map(function(item, index) {
        return {
          id: Number(item.id),
          label: String(item.label || item.id),
          x: Number.isFinite(Number(item.x)) ? Number(item.x) : index,
          y: Number.isFinite(Number(item.y)) ? Number(item.y) : 0
        };
      });
      if (parsed.length > 0)
        return parsed;
    } catch (error) {
      console.error("desktop-shell: invalid workspace topology: " + error);
    }
    return [
      { id: 1, label: "I", x: 0, y: 0 },
      { id: 2, label: "II", x: 1, y: 0 },
      { id: 3, label: "III", x: 2, y: 0 },
      { id: 4, label: "IV", x: 3, y: 0 },
      { id: 5, label: "V", x: 4, y: 0 }
    ];
  }

  readonly property var workspaceIds: workspaces.map(function(workspace) {
    return workspace.id;
  })

  readonly property var keyboardLayoutLabels: {
    try {
      const parsed = JSON.parse(Quickshell.env("DESKTOP_SHELL_KEYBOARD_LABELS_JSON") || "[]");
      if (Array.isArray(parsed) && parsed.length > 0)
        return parsed.map(function(label) { return String(label); });
    } catch (error) {
      console.error("desktop-shell: invalid keyboard layout labels: " + error);
    }
    return ["EN"];
  }

  readonly property var launchProfiles: {
    try {
      const parsed = JSON.parse(Quickshell.env("DESKTOP_SHELL_LAUNCH_PROFILES_JSON") || "{}");
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        throw new Error("expected an object");

      const profiles = ({});
      for (const id of Object.keys(parsed)) {
        const profile = parsed[id];
        const applications = profile?.applications;
        if (!/^[a-z0-9][a-z0-9-]*$/.test(id)
            || !profile
            || typeof profile !== "object"
            || Array.isArray(profile)
            || !Array.isArray(applications)
            || applications.length === 0)
          continue;

        const normalizedApplications = [];
        for (const application of applications) {
          const entryId = String(application?.id || "");
          const workspace = Number(application?.workspace);
          if (!/^[A-Za-z0-9_.+-]+\.desktop$/.test(entryId)
              || !Number.isInteger(workspace)
              || workspace <= 0)
            continue;
          normalizedApplications.push({ id: entryId, workspace: workspace });
        }
        if (normalizedApplications.length !== applications.length)
          continue;

        profiles[id] = {
          label: String(profile.label || id),
          icon: String(profile.icon || ""),
          applications: normalizedApplications
        };
      }
      return profiles;
    } catch (error) {
      console.error("desktop-shell: invalid launch profiles: " + error);
      return ({});
    }
  }

  function keyboardLayoutLabel(index) {
    const numericIndex = Math.max(0, Number(index || 0));
    const label = String(keyboardLayoutLabels[numericIndex] || "").trim();
    return label.length > 0 ? label : "--";
  }

  function workspace(id) {
    const numericId = Number(id);
    return workspaces.find(function(item) { return item.id === numericId; }) || null;
  }

  function workspaceLabel(id) {
    const item = workspace(id);
    return item ? item.label : String(id);
  }

  function workspacePoint(id) {
    const item = workspace(id);
    return item ? { x: item.x, y: item.y } : { x: 0, y: 0 };
  }
}
