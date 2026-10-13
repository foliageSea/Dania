import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/toolbox/models.dart';
import 'toolbox_widgets.dart';

class TransferProgress extends StatelessWidget {
  const TransferProgress({
    required this.done,
    this.total,
    required this.cancel,
    super.key,
  });
  final int done;
  final int? total;
  final VoidCallback cancel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        if (total != null && total! > 0)
          FDeterminateProgress(value: (done / total!).clamp(0, 1))
        else
          const FProgress(),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: .center,
          children: [
            Text(
              '${formatBytes(done)}${total != null ? ' / ${formatBytes(total!)}' : ''}',
            ),
            ToolButton(context.tx('取消', 'Cancel'), onPress: cancel),
          ],
        ),
      ],
    ),
  );
}
