Name:       harbour-weatherchart
Version:    1.1.2
Release:    1
Summary:    Weather forecast in charts (Klara-style) for Sailfish OS
License:    GPLv3
URL:        https://github.com/mig1984/harbour-weatherchart
BuildArch:  noarch
Source0:    %{name}-%{version}.tar.gz

Requires:   sailfishsilica-qt5
Requires:   libsailfishapp-launcher
Requires:   qt5-qtdeclarative-import-positioning
Requires:   nemo-qml-plugin-configuration-qt5

%description
Weather Chart shows the short-term (3 days) and long-term (7 days) forecast
as a chart: temperature curve (blue below freezing), precipitation bars
(blue rain, white snow), wind speed with direction arrows and cloud cover.
Data from Open-Meteo. Saved locations, GPS location, tap in the chart to
inspect a specific time.

%prep
%setup -q

%build
# nothing to build, pure QML

%install
rm -rf %{buildroot}
install -d %{buildroot}%{_datadir}/%{name}/qml/pages
install -d %{buildroot}%{_datadir}/%{name}/qml/cover
install -d %{buildroot}%{_datadir}/%{name}/qml/components
install -d %{buildroot}%{_datadir}/%{name}/qml/js
install -m 644 qml/%{name}.qml %{buildroot}%{_datadir}/%{name}/qml/
install -m 644 qml/pages/*.qml %{buildroot}%{_datadir}/%{name}/qml/pages/
install -m 644 qml/cover/*.qml %{buildroot}%{_datadir}/%{name}/qml/cover/
install -m 644 qml/components/*.qml %{buildroot}%{_datadir}/%{name}/qml/components/
install -m 644 qml/js/*.js %{buildroot}%{_datadir}/%{name}/qml/js/
install -d %{buildroot}%{_datadir}/applications
install -m 644 %{name}.desktop %{buildroot}%{_datadir}/applications/
for s in 86 108 128 172; do
    install -d %{buildroot}%{_datadir}/icons/hicolor/${s}x${s}/apps
    install -m 644 icons/${s}x${s}/%{name}.png %{buildroot}%{_datadir}/icons/hicolor/${s}x${s}/apps/
done

%files
%defattr(-,root,root,-)
%license LICENSE
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Mon Nov 16 2026 Jan Molič <jan.molic@1984.cz> - 1.1.0-1
- GPLv3 license
- Finnish and Simplified Chinese UI strings
- Spec URL fixed to the GitHub repository

* Mon Nov 16 2026 Jan Molič <jan.molic@1984.cz> - 1.0.0-1
- First stable release, repository published on GitHub
* Sat Nov 14 2026 mig - 0.1.8-1
- Forecast refreshes every 10 minutes, also while minimized (cover)
* Sat Nov 14 2026 mig - 0.1.7-1
- Clouds mode: temperature curve drawn over the clouds
* Sat Nov 14 2026 mig - 0.1.6-1
- Wind mode: wind curve back to green, gust line in orange
* Sat Nov 14 2026 mig - 0.1.5-1
- Wind curve outline in the same orange as the temperature curve
* Sat Nov 14 2026 mig - 0.1.4-1
- Mode icons doubled in size
* Sat Nov 14 2026 mig - 0.1.3-1
- Mode icons moved to the top left, on the level of the location name
- Mode icons are repainted when the app is activated (no longer vanish)
* Mon Nov 09 2026 mig - 0.1.0-1
- Initial release
