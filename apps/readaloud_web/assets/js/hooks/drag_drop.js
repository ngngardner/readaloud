// Drag-and-drop file upload hook for LiveView
const DragDropHook = {
	mounted() {
		const zone = this.el;
		const overlay = zone.querySelector("[data-drop-overlay]");

		["dragenter", "dragover"].forEach((evt) => {
			zone.addEventListener(evt, (e) => {
				e.preventDefault();
				if (overlay) overlay.classList.remove("hidden");
			});
		});

		["dragleave", "drop"].forEach((evt) => {
			zone.addEventListener(evt, (e) => {
				e.preventDefault();
				if (overlay) overlay.classList.add("hidden");
			});
		});

		zone.addEventListener("drop", (e) => {
			const files = e.dataTransfer.files;
			if (files.length > 0) {
				const input = zone.querySelector("input[type=file]");
				if (input) {
					const dt = new DataTransfer();
					for (const f of files) dt.items.add(f);
					input.files = dt.files;
					input.dispatchEvent(new Event("change", { bubbles: true }));
				}
			}
		});
	},
};

export default DragDropHook;
