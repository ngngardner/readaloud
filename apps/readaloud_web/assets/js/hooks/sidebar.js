const SidebarHook = {
	mounted() {
		const sidebar = this.el;
		const toggle = document.getElementById("sidebar-toggle");
		const backdrop = document.getElementById("sidebar-backdrop");
		// Only hide text labels on collapse, not icon spans
		const labels = sidebar.querySelectorAll("span.whitespace-nowrap");

		// Desktop: show labels when sidebar is hovered (expand on hover)
		sidebar.addEventListener("mouseenter", () => {
			for (const el of labels) el.style.opacity = "1";
		});
		sidebar.addEventListener("mouseleave", () => {
			for (const el of labels) el.style.opacity = "0";
		});

		// Mobile toggle
		if (toggle) {
			toggle.addEventListener("click", () => {
				const isOpen = !sidebar.classList.contains(
					"max-sm:translate-x-[-100%]",
				);
				if (isOpen) {
					sidebar.classList.add("max-sm:translate-x-[-100%]");
					backdrop.classList.add("hidden");
				} else {
					sidebar.classList.remove("max-sm:translate-x-[-100%]");
					backdrop.classList.remove("hidden");
					for (const el of labels) el.style.opacity = "1";
				}
			});
		}

		if (backdrop) {
			backdrop.addEventListener("click", () => {
				sidebar.classList.add("max-sm:translate-x-[-100%]");
				backdrop.classList.add("hidden");
			});
		}
	},
};

export default SidebarHook;
