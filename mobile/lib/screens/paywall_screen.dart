import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  /// Push the paywall screen. Returns true if the user subscribed.
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    return result ?? false;
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _purchasing = false;
  bool _restoring = false;
  String? _error;
  int _selectedIndex = 0; // 0 = monthly, 1 = annual

  @override
  Widget build(BuildContext context) {
    final sub = Provider.of<SubscriptionService>(context);
    final offering = sub.offerings?.current;
    final packages = offering?.availablePackages ?? [];

    // Sort: monthly first, then annual
    final sorted = List<Package>.from(packages)
      ..sort((a, b) {
        const order = {
          PackageType.monthly: 0,
          PackageType.annual: 1,
        };
        return (order[a.packageType] ?? 2).compareTo(order[b.packageType] ?? 2);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 28),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Hero icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 48,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'IamSafe Premium',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Extra peace of mind for your family',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Feature list
              const _FeatureRow(icon: Icons.sms, text: 'SMS alerts when check-in is missed'),
              const SizedBox(height: 12),
              const _FeatureRow(icon: Icons.history, text: 'Unlimited check-in history'),
              const SizedBox(height: 12),
              const _FeatureRow(icon: Icons.camera_alt, text: 'Full selfie history'),
              const SizedBox(height: 12),
              const _FeatureRow(icon: Icons.people, text: 'Multiple caregivers'),

              const SizedBox(height: 32),

              // Package selector
              if (sorted.isEmpty)
                const Text(
                  'Subscriptions are not available right now.\nPlease try again later.',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                )
              else ...[
                ...sorted.asMap().entries.map((entry) {
                  final i = entry.key;
                  final pkg = entry.value;
                  final selected = i == _selectedIndex;
                  final isAnnual = pkg.packageType == PackageType.annual;
                  final price = pkg.storeProduct.priceString;
                  final period = isAnnual ? '/year' : '/month';

                  return GestureDetector(
                    onTap: () => setState(() => _selectedIndex = i),
                    child: Semantics(
                      selected: selected,
                      label: '${isAnnual ? "Annual" : "Monthly"} plan, $price $period',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primaryGreen.withAlpha(20)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? AppTheme.primaryGreen : Colors.grey[300]!,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected
                                  ? AppTheme.primaryGreen
                                  : AppTheme.textSecondary,
                              size: 28,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAnnual ? 'Annual' : 'Monthly',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (isAnnual)
                                    const Text(
                                      'Save ~33%',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: AppTheme.primaryGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '$price$period',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.alertRed,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const Spacer(),

              // Purchase button
              if (sorted.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _purchasing ? null : () => _onPurchase(sorted),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryGreen.withAlpha(128),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _purchasing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Subscribe',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

              const SizedBox(height: 12),

              // Restore purchases
              TextButton(
                onPressed: _restoring ? null : _onRestore,
                child: _restoring
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Restore Purchases',
                        style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                      ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPurchase(List<Package> sorted) async {
    if (_selectedIndex >= sorted.length) return;

    setState(() {
      _purchasing = true;
      _error = null;
    });

    final sub = Provider.of<SubscriptionService>(context, listen: false);
    final success = await sub.purchase(sorted[_selectedIndex]);

    setState(() => _purchasing = false);

    if (success && mounted) {
      Navigator.pop(context, true);
    } else if (mounted) {
      setState(() => _error = 'Purchase could not be completed. Please try again.');
    }
  }

  Future<void> _onRestore() async {
    setState(() {
      _restoring = true;
      _error = null;
    });

    final sub = Provider.of<SubscriptionService>(context, listen: false);
    final success = await sub.restore();

    setState(() => _restoring = false);

    if (success && mounted) {
      Navigator.pop(context, true);
    } else if (mounted) {
      setState(() => _error = 'No active subscription found.');
    }
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 28, color: AppTheme.primaryGreen),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ],
    );
  }
}
