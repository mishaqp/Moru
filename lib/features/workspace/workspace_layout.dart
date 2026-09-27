import 'package:flutter/widgets.dart';

import 'package:Kelivo/shared/responsive/screen_type_helper.dart';

/// Large screens (tablets, foldables in landscape) use dialogs and side panes.
bool useDesktopWorkspaceLayout(BuildContext context) =>
    ResponsiveHelper.isDesktop(context);
